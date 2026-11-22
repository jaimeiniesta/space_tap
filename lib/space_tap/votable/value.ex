defmodule SpaceTAP.VOTable.Value do
  @moduledoc false

  # Turns one cell into an Elixir value, following the datatype and arraysize
  # of its field (VOTable 1.5 §6) and ADR 0007: the text of a TABLEDATA cell
  # (§5.1), or the bytes of a BINARY or BINARY2 one (§5.3, §5.4).
  #
  # What the field says about every one of its cells is read once, by
  # prepare/1, into the decoder the other functions take: a table has as
  # many cells of a field as rows, and the arraysize and the null value take
  # some parsing. A field SpaceTAP can't read has no decoder, so it is an
  # error even when no cell uses it: a table may have no rows, and an empty
  # TD is nil before anything else is read.

  alias SpaceTAP.Field

  # No service in the README's Compatibility table has sent these, and a
  # complex number would need an Elixir value ADR 0007 doesn't choose.
  @unsupported [:bit, :floatComplex, :doubleComplex]

  @string_datatypes [:char, :unicodeChar]

  # The white space of §5.1, which matters only in strings.
  @whitespace [" ", "\t", "\n", "\r"]

  # The bits of each integer datatype, which also give the number of
  # hexadigits it may have (§6).
  @integer_bits %{unsignedByte: 8, short: 16, int: 32, long: 64}

  # The characters an integer takes at most, the sign and the 19 digits of
  # a long, and the digits of a dimension, those of an int: a longer text
  # is read by no datatype, and Integer.parse/1 would take millions of
  # digits, and raise SystemLimitError beyond them.
  @integer_characters 20
  @dimension_digits 10

  # §2.2 bounds the number of dimensions nowhere, but nest/2 costs the
  # elements times the dimensions, and no service writes more than three.
  @max_dimensions 16

  # The bytes of one element of each datatype in BINARY and BINARY2 (§2.1),
  # which are also the units a string is counted in: a char is ASCII (§6),
  # one byte, and a unicodeChar a UTF-16 unit of two (ADR 0007).
  @element_bytes %{
    boolean: 1,
    unsignedByte: 1,
    short: 2,
    int: 4,
    long: 8,
    char: 1,
    unicodeChar: 2,
    float: 4,
    double: 8
  }

  # The decoder of the cells of one field: the field itself, which its
  # errors name, its datatype, its shape, its null value read as a value of
  # the datatype, and the bytes of one element.
  @enforce_keys [:field, :datatype, :shape, :null, :bytes]
  defstruct [:field, :datatype, :shape, :null, :bytes]

  @type t :: %__MODULE__{
          field: Field.t(),
          datatype: Field.datatype(),
          shape: shape(),
          null: term(),
          bytes: 1 | 2 | 4 | 8
        }

  # A field without arraysize holds one element (§2.1). Otherwise, the fixed
  # dimensions and the last one (§2.2): dimensions separated by "x", the
  # first changing fastest, and only the last one variable, so "N*" holds up
  # to N elements and "*" any number.
  @type shape :: :scalar | {[pos_integer()], pos_integer() | {:at_most, pos_integer()} | :any}

  @spec prepare(Field.t()) :: {:ok, t()} | {:error, String.t()}
  def prepare(%Field{datatype: datatype} = field) when datatype in @unsupported,
    do: unsupported(field)

  def prepare(%Field{datatype: datatype} = field) do
    with {:ok, shape} <- shape(field),
         {:ok, null} <- null(field) do
      {:ok,
       %__MODULE__{
         field: field,
         datatype: datatype,
         shape: shape,
         null: null,
         bytes: Map.fetch!(@element_bytes, datatype)
       }}
    end
  end

  @spec parse_text(String.t(), t()) :: {:ok, term()} | {:error, String.t()}
  def parse_text("", %__MODULE__{}), do: {:ok, nil}

  # A string is an array of characters, written with no separator and with
  # its white space (§5.1).
  def parse_text(text, %__MODULE__{datatype: datatype} = decoder)
      when datatype in @string_datatypes do
    case encode(text, datatype) do
      {:ok, encoded} -> string(text, encoded, decoder)
      :error -> invalid(text, decoder)
    end
  end

  def parse_text(text, %__MODULE__{shape: :scalar} = decoder) do
    case token(text) do
      :none -> {:ok, nil}
      {:ok, token} -> scalar(token, decoder)
      :many -> invalid(text, decoder)
    end
  end

  # The numbers of an array are separated by white space (§5.1). An array
  # with none is nil, since TABLEDATA writes it like a null (§5.5).
  def parse_text(text, %__MODULE__{} = decoder) do
    case String.split(text, @whitespace, trim: true) do
      [] -> {:ok, nil}
      tokens -> array(tokens, text, decoder)
    end
  end

  # BINARY writes the cells of a row one after another, with no separator,
  # and their numbers big-endian (§5.3). BINARY2 adds the null flags of each
  # row, which Binary.rows/3 reads (§5.4). Returns the bytes after the cell.
  @spec parse_binary(binary(), t()) :: {:ok, term(), binary()} | {:error, String.t()}
  def parse_binary(bytes, %__MODULE__{} = decoder) do
    with {:ok, cell, rest} <- split_cell(bytes, decoder),
         {:ok, value} <- binary_value(cell, decoder),
         do: {:ok, value, rest}
  end

  # BINARY2 flags a null cell, but its bytes are still there, and §5.4 only
  # recommends what they hold: NaN or zeros, and a length of 0 for a
  # variable-length array. So they are skipped without reading them, though
  # the layout of the cell is checked as in parse_binary/2.
  @spec skip_binary(binary(), t()) :: {:ok, binary()} | {:error, String.t()}
  def skip_binary(bytes, %__MODULE__{} = decoder) do
    with {:ok, _cell, rest} <- split_cell(bytes, decoder), do: {:ok, rest}
  end

  #####################
  # Private functions #
  #####################

  defp scalar(token, %{datatype: datatype, null: null} = decoder) do
    case element(token, datatype) do
      {:ok, value} -> {:ok, unless_null(value, null)}
      :error -> invalid(token, decoder)
    end
  end

  defp array(tokens, text, %{shape: {fixed, _last} = shape} = decoder) do
    if fits?(length(tokens), shape) do
      with {:ok, values} <- elements(tokens, decoder, []), do: {:ok, nest(values, fixed)}
    else
      doesnt_fit(text, decoder)
    end
  end

  # A string in the elements of its datatype, which count its characters: a
  # char is ASCII (§6), one byte each, and a unicodeChar is counted in UTF-16
  # units, the two bytes it takes in BINARY, so a character beyond U+FFFF
  # counts twice (ADR 0007). Saxy hands over valid UTF-8 only, but text that
  # isn't is an error here too, not a crash.
  defp encode(text, :char), do: if(ascii?(text), do: {:ok, text}, else: :error)

  defp encode(text, :unicodeChar) do
    case :unicode.characters_to_binary(text, :utf8, {:utf16, :big}) do
      encoded when is_binary(encoded) -> {:ok, encoded}
      _invalid_or_incomplete -> :error
    end
  end

  # A field without arraysize holds one character (§2.1).
  defp string(text, encoded, %{shape: :scalar, bytes: bytes} = decoder) do
    if byte_size(encoded) == bytes,
      do: {:ok, unless_null(text, decoder.null)},
      else: invalid(text, decoder)
  end

  # A fixed size is the most characters a string holds, since §5.1 writes
  # Apple in an arraysize of 10. §4.7 says the null value is never an array,
  # but a string is an array of characters, so the null value of a string
  # field is compared with each whole string.
  defp string(text, encoded, %{shape: {[], last}, bytes: bytes} = decoder) do
    last = if is_integer(last), do: {:at_most, last}, else: last

    if fits_last?(div(byte_size(encoded), bytes), last),
      do: {:ok, unless_null(text, decoder.null)},
      else: doesnt_fit(text, decoder)
  end

  # The strings of a multidimensional array fill the first dimension:
  # without a separator, that is the only way to tell where each one ends.
  # They are cut where BINARY would cut them, so a character beyond U+FFFF
  # split between two of them is a lone surrogate in each, an error.
  defp string(text, encoded, %{shape: {[size | fixed], _last} = shape, bytes: bytes} = decoder) do
    if fits?(div(byte_size(encoded), bytes), shape) do
      case text_strings(encoded, size * bytes, decoder, []) do
        {:ok, strings} -> {:ok, nest(strings, fixed)}
        :error -> invalid(text, decoder)
      end
    else
      doesnt_fit(text, decoder)
    end
  end

  defp text_strings(<<>>, _bytes, _decoder, strings), do: {:ok, Enum.reverse(strings)}

  defp text_strings(encoded, bytes, decoder, strings) do
    {string, rest} = :erlang.split_binary(encoded, bytes)

    with {:ok, string} <- text(string, decoder.datatype),
         do: text_strings(rest, bytes, decoder, [unless_null(string, decoder.null) | strings])
  end

  # The null value is one TABLEDATA value of the datatype (§4.7). It is read
  # like a cell, so 0x8000 and -32768 are the same null of a short. A field
  # without one gets nil, which turns nothing into nil. The null value of a
  # string is its text, compared with each whole string, and that of a char
  # is ASCII, like its cells (§6).
  defp null(%Field{datatype: :char, null: text} = field) when is_binary(text),
    do: if(ascii?(text), do: {:ok, text}, else: invalid_null(text, field))

  defp null(%Field{datatype: datatype, null: text}) when datatype in @string_datatypes,
    do: {:ok, text}

  defp null(%Field{null: nil}), do: {:ok, nil}

  defp null(%Field{null: text, datatype: datatype} = field) do
    with {:ok, token} <- token(text),
         {:ok, value} <- element(token, datatype) do
      {:ok, value}
    else
      _other -> invalid_null(text, field)
    end
  end

  defp unless_null(value, null), do: if(value == null, do: nil, else: value)

  # The one value of a scalar, between any white space (§5.1): what
  # String.split/3 would give, without building the list or compiling the
  # pattern for each cell.
  defp token(text) do
    case skip_whitespace(text) do
      "" ->
        :none

      text ->
        {token, rest} = :erlang.split_binary(text, token_size(text, 0))
        if skip_whitespace(rest) == "", do: {:ok, token}, else: :many
    end
  end

  defp skip_whitespace(<<char, rest::binary>>) when char in ~c" \t\n\r",
    do: skip_whitespace(rest)

  defp skip_whitespace(text), do: text

  defp token_size(<<char, _rest::binary>>, size) when char in ~c" \t\n\r", do: size
  defp token_size(<<_char, rest::binary>>, size), do: token_size(rest, size + 1)
  defp token_size(<<>>, size), do: size

  # Each element of an array is checked against the null value, the only way
  # to mark one of them as null (§5.5).
  defp elements([], _decoder, values), do: {:ok, Enum.reverse(values)}

  defp elements([token | tokens], %{datatype: datatype, null: null} = decoder, values) do
    case element(token, datatype) do
      {:ok, value} -> elements(tokens, decoder, [unless_null(value, null) | values])
      :error -> invalid(token, decoder)
    end
  end

  # The first dimension changes fastest (§2.2), so it makes the innermost lists.
  defp nest(values, []), do: values
  defp nest(values, [size | fixed]), do: values |> Enum.chunk_every(size) |> nest(fixed)

  # The shape of the cells, from the arraysize: the fixed dimensions and the
  # last one, or :scalar without one.
  defp shape(%Field{arraysize: nil}), do: {:ok, :scalar}

  defp shape(%Field{arraysize: arraysize} = field) do
    dimensions = String.split(arraysize, "x")
    {fixed, [last]} = Enum.split(dimensions, -1)

    with true <- length(dimensions) <= @max_dimensions,
         {:ok, fixed} <- dimensions(fixed),
         {:ok, last} <- last_dimension(last) do
      {:ok, {fixed, last}}
    else
      _invalid ->
        {:error, "field #{inspect(field.name)}: #{inspect(arraysize)} is not a valid arraysize"}
    end
  end

  defp dimensions([]), do: {:ok, []}

  defp dimensions([text | texts]) do
    with {:ok, size} <- size(text),
         {:ok, sizes} <- dimensions(texts),
         do: {:ok, [size | sizes]}
  end

  defp last_dimension("*"), do: {:ok, :any}

  defp last_dimension(text) do
    case String.split_at(text, -1) do
      {size, "*"} -> with {:ok, size} <- size(size), do: {:ok, {:at_most, size}}
      _fixed -> size(text)
    end
  end

  defp size(text) do
    with {digits, ""} when digits != "" and byte_size(digits) <= @dimension_digits <-
           split_digits(text),
         size when size > 0 <- String.to_integer(digits) do
      {:ok, size}
    else
      _other -> :error
    end
  end

  # Whether a number of elements fills whole arrays of the fixed dimensions,
  # as many as the last dimension takes: exactly N, up to N for "N*", or any
  # number for "*".
  defp fits?(count, {fixed, last}) do
    inner = Enum.product(fixed)
    rem(count, inner) == 0 and fits_last?(div(count, inner), last)
  end

  defp fits_last?(_count, :any), do: true
  defp fits_last?(count, {:at_most, size}), do: count <= size
  defp fits_last?(count, size), do: count == size

  defp ascii?(<<char, rest::binary>>) when char < 128, do: ascii?(rest)
  defp ascii?(rest), do: rest == ""

  defp element(token, :boolean), do: boolean(token)

  defp element(token, datatype) when is_map_key(@integer_bits, datatype),
    do: integer(token, Map.fetch!(@integer_bits, datatype), datatype)

  # The special values are written exactly like this (§6). A BEAM float can't
  # be NaN or infinite, so NaN is nil and the infinities are the atoms
  # Explorer uses (ADR 0007).
  defp element("NaN", datatype) when datatype in [:float, :double], do: {:ok, nil}
  defp element("+Inf", datatype) when datatype in [:float, :double], do: {:ok, :infinity}
  defp element("-Inf", datatype) when datatype in [:float, :double], do: {:ok, :neg_infinity}
  defp element(token, :double), do: decimal(token)

  # A float is the double nearest to the text rounded to 32 bits, the same
  # value its four bytes give in BINARY2 (ADR 0007). A number beyond the
  # largest float rounds to the bits of an infinity, which no BEAM float
  # matches.
  defp element(token, :float) do
    with {:ok, double} <- decimal(token) do
      case <<double::float-32>> do
        <<float::float-32>> -> {:ok, float}
        _infinity -> :error
      end
    end
  end

  # TABLEDATA takes "true" and "false" in any case besides the letters and
  # digits of BINARY, and "?" is null (§6).
  defp boolean(token) when token in ["T", "t", "1"], do: {:ok, true}
  defp boolean(token) when token in ["F", "f", "0"], do: {:ok, false}
  defp boolean("?"), do: {:ok, nil}

  defp boolean(token) do
    case String.downcase(token, :ascii) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _other -> :error
    end
  end

  defp integer(text, _bits, _datatype) when byte_size(text) > @integer_characters, do: :error

  # The hexadecimal representation gives the bits the BINARY serialization
  # would hold, so 0xFFFF is -1 in a short, as it would be there: §6 gives the
  # number of hexadigits for each datatype, but not their sign.
  defp integer("0x" <> hex, bits, datatype) when byte_size(hex) in 1..div(bits, 4)//1 do
    if hexadigits?(hex) do
      {:ok, bit_pattern(String.to_integer(hex, 16), bits, datatype)}
    else
      :error
    end
  end

  defp integer(text, bits, datatype) do
    {min, max} = range(bits, datatype)

    case Integer.parse(text) do
      {integer, ""} when integer in min..max//1 -> {:ok, integer}
      _other -> :error
    end
  end

  # §6: an optional sign, a positive decimal number such as 1, 1.5, 1. or .5,
  # and an optional exponent made of "E" or "e", an optional sign and digits.
  # The digits of the exponent aren't counted, although §6 allows 1 or 2 in a
  # float and 1 to 3 in a double. to_float/1 gets the number with a zero
  # before and after the point, a form it always reads, and fails only when
  # the number is beyond the largest double.
  defp decimal(text) do
    {sign, text} = split_sign(text)
    {integer, text} = split_digits(text)
    {fraction, text} = split_fraction(text)

    case {integer <> fraction, exponent(text)} do
      {"", _exponent} ->
        :error

      {_digits, :error} ->
        :error

      {_digits, {:ok, exponent}} ->
        to_float(
          <<sign::binary, ?0, integer::binary, ?., fraction::binary, "0e", exponent::binary>>
        )
    end
  end

  defp split_sign("+" <> rest), do: {"+", rest}
  defp split_sign("-" <> rest), do: {"-", rest}
  defp split_sign(text), do: {"", text}

  # Splits off the digits a text starts with, without copying them.
  defp split_digits(text), do: :erlang.split_binary(text, count_digits(text, 0))

  defp count_digits(<<digit, rest::binary>>, count) when digit in ?0..?9,
    do: count_digits(rest, count + 1)

  defp count_digits(_text, count), do: count

  defp split_fraction("." <> rest), do: split_digits(rest)
  defp split_fraction(text), do: {"", text}

  defp exponent(""), do: {:ok, "0"}

  defp exponent(<<letter, rest::binary>>) when letter in [?E, ?e] do
    {sign, rest} = split_sign(rest)

    case split_digits(rest) do
      {"", _rest} -> :error
      {digits, ""} -> {:ok, sign <> digits}
      {_digits, _rest} -> :error
    end
  end

  defp exponent(_text), do: :error

  # The text is always in the form :erlang.binary_to_float/1 reads, the one
  # Float.parse/1 hands it after reading the text character by character.
  defp to_float(text) do
    {:ok, :erlang.binary_to_float(text)}
  rescue
    ArgumentError -> :error
  end

  defp hexadigits?(<<char, rest::binary>>)
       when char in ?0..?9 or char in ?a..?f or char in ?A..?F,
       do: rest == "" or hexadigits?(rest)

  defp hexadigits?(_text), do: false

  # unsignedByte is the only unsigned integer datatype (§2.1).
  defp bit_pattern(unsigned, _bits, :unsignedByte), do: unsigned

  # Two's complement (§6): a set top bit makes the number negative.
  defp bit_pattern(unsigned, bits, _datatype) do
    top = Bitwise.bsl(1, bits - 1)
    if unsigned < top, do: unsigned, else: unsigned - 2 * top
  end

  defp range(_bits, :unsignedByte), do: {0, 255}
  defp range(bits, _datatype), do: {-Bitwise.bsl(1, bits - 1), Bitwise.bsl(1, bits - 1) - 1}

  # The bytes of the elements of a cell, with the bytes after it.
  defp split_cell(bytes, %{shape: shape, bytes: unit} = decoder) do
    with {:ok, count, bytes} <- element_count(bytes, shape, decoder),
         do: take(bytes, count * unit, decoder)
  end

  # The bytes of a cell, split off without copying them.
  defp take(bytes, size, _decoder) when byte_size(bytes) >= size do
    {cell, rest} = :erlang.split_binary(bytes, size)
    {:ok, cell, rest}
  end

  defp take(_bytes, _size, %{field: %Field{name: name}}),
    do: {:error, "field #{inspect(name)}: the data ends in the middle of the cell"}

  # §5.3: a variable-length array starts with its length, a 4-byte integer.
  # Only the last dimension may vary (§2.2), so in "3x*" the length counts
  # arrays of 3 elements, as astropy reads it.
  defp element_count(bytes, :scalar, _decoder), do: {:ok, 1, bytes}

  defp element_count(bytes, {fixed, last}, _decoder) when is_integer(last),
    do: {:ok, Enum.product(fixed) * last, bytes}

  defp element_count(<<length::unsigned-big-32, rest::binary>>, {fixed, last}, decoder) do
    if fits_last?(length, last) do
      {:ok, Enum.product(fixed) * length, rest}
    else
      %Field{name: name, arraysize: arraysize} = decoder.field

      {:error,
       "field #{inspect(name)}: a length of #{length} doesn't fit arraysize #{inspect(arraysize)}"}
    end
  end

  defp element_count(_bytes, _shape, decoder), do: take(<<>>, 4, decoder)

  # One character is a string of one, cut at a NUL like any fixed one.
  defp binary_value(cell, %{shape: :scalar, datatype: datatype} = decoder)
       when datatype in @string_datatypes,
       do: binary_string(before_nul(cell, datatype), decoder)

  # The cell of a scalar is the bytes of its one element, no more.
  defp binary_value(cell, %{shape: :scalar, datatype: datatype, null: null} = decoder) do
    case binary_element(cell, datatype) do
      {:ok, value, <<>>} -> {:ok, unless_null(value, null)}
      :error -> invalid(cell, decoder)
    end
  end

  # An array with no elements and a string with no characters are nil
  # (ADR 0007).
  defp binary_value(<<>>, _decoder), do: {:ok, nil}

  # A string ends where the length of a variable arraysize says, so only a
  # fixed one is cut at a NUL, as astropy reads them.
  defp binary_value(cell, %{shape: {[], last}, datatype: datatype} = decoder)
       when datatype in @string_datatypes do
    if is_integer(last),
      do: binary_string(before_nul(cell, datatype), decoder),
      else: binary_string(cell, decoder)
  end

  # Each string of a multidimensional array takes the whole first dimension,
  # so it is a fixed one.
  defp binary_value(cell, %{shape: {[size | fixed], _last}, datatype: datatype} = decoder)
       when datatype in @string_datatypes do
    with {:ok, strings} <- binary_strings(cell, size * decoder.bytes, decoder, []),
         do: {:ok, nest(strings, fixed)}
  end

  defp binary_value(cell, %{shape: {fixed, _last}} = decoder) do
    with {:ok, values} <- binary_elements(cell, decoder, []), do: {:ok, nest(values, fixed)}
  end

  defp binary_strings(<<>>, _bytes, _decoder, strings), do: {:ok, Enum.reverse(strings)}

  defp binary_strings(cell, bytes, decoder, strings) do
    {string, rest} = :erlang.split_binary(cell, bytes)

    with {:ok, string} <- binary_string(before_nul(string, decoder.datatype), decoder),
         do: binary_strings(rest, bytes, decoder, [string | strings])
  end

  defp binary_elements(<<>>, _decoder, values), do: {:ok, Enum.reverse(values)}

  defp binary_elements(bytes, %{datatype: datatype, null: null} = decoder, values) do
    case binary_element(bytes, datatype) do
      {:ok, value, rest} -> binary_elements(rest, decoder, [unless_null(value, null) | values])
      :error -> invalid(binary_part(bytes, 0, decoder.bytes), decoder)
    end
  end

  # A boolean is one of the ASCII characters of §6, so the byte 1 isn't true.
  defp binary_element(<<byte, rest::binary>>, :boolean) when byte in [?T, ?t, ?1],
    do: {:ok, true, rest}

  defp binary_element(<<byte, rest::binary>>, :boolean) when byte in [?F, ?f, ?0],
    do: {:ok, false, rest}

  defp binary_element(<<byte, rest::binary>>, :boolean) when byte in [0x00, ?\s, ??],
    do: {:ok, nil, rest}

  defp binary_element(<<_byte, _rest::binary>>, :boolean), do: :error

  # Integers are two's complement but unsignedByte (§6).
  defp binary_element(<<value, rest::binary>>, :unsignedByte), do: {:ok, value, rest}
  defp binary_element(<<value::signed-16, rest::binary>>, :short), do: {:ok, value, rest}
  defp binary_element(<<value::signed-32, rest::binary>>, :int), do: {:ok, value, rest}
  defp binary_element(<<value::signed-64, rest::binary>>, :long), do: {:ok, value, rest}

  # IEEE 754 (§6): an exponent of all ones is an infinity when the fraction
  # is zero and NaN otherwise, bits that no BEAM float matches. Any other
  # four bytes of a float give the exact value of its 32 bits (ADR 0007).
  defp binary_element(<<sign::1, 0xFF::8, fraction::23, rest::binary>>, :float),
    do: {:ok, special(sign, fraction), rest}

  defp binary_element(<<value::float-32, rest::binary>>, :float), do: {:ok, value, rest}

  defp binary_element(<<sign::1, 0x7FF::11, fraction::52, rest::binary>>, :double),
    do: {:ok, special(sign, fraction), rest}

  defp binary_element(<<value::float-64, rest::binary>>, :double), do: {:ok, value, rest}

  defp special(_sign, fraction) when fraction > 0, do: nil
  defp special(0, 0), do: :infinity
  defp special(1, 0), do: :neg_infinity

  # §6: a char string follows the FITS rules, so a fixed one may end with a
  # NUL before its arraysize, and what comes after isn't defined. A
  # unicodeChar NUL is two zero bytes, on a character boundary.
  defp before_nul(bytes, :char) do
    case :binary.match(bytes, <<0>>) do
      {at, 1} -> binary_part(bytes, 0, at)
      :nomatch -> bytes
    end
  end

  defp before_nul(bytes, :unicodeChar), do: binary_part(bytes, 0, nul_at(bytes, 0))

  defp nul_at(<<0, 0, _rest::binary>>, at), do: at
  defp nul_at(<<_character::binary-2, rest::binary>>, at), do: nul_at(rest, at + 2)
  defp nul_at(<<>>, at), do: at

  # A char is ASCII. §6 calls the two bytes of a unicodeChar UCS-2, which
  # holds no character beyond U+FFFF; they are read as UTF-16, as astropy
  # does, so a surrogate pair is one character and a lone surrogate is an
  # error (ADR 0007). A string with no characters is nil (ADR 0007).
  defp binary_string(bytes, %{datatype: datatype, null: null} = decoder) do
    case text(bytes, datatype) do
      {:ok, ""} -> {:ok, nil}
      {:ok, string} -> {:ok, string |> unless_null(null) |> own(datatype)}
      :error -> invalid(bytes, decoder)
    end
  end

  # A char string is the bytes of the stream themselves, and one of more than
  # 64 bytes would stay a reference into the stream, keeping all of it in
  # memory for as long as the string lives, however little of the result is
  # left. So it gets a binary of its own: 10 ms for 200,000 strings. A
  # unicodeChar string is already one, and the runtime copies a shorter one.
  defp own(nil, _datatype), do: nil
  defp own(string, :char), do: :binary.copy(string)
  defp own(string, :unicodeChar), do: string

  defp text(bytes, :char), do: if(ascii?(bytes), do: {:ok, bytes}, else: :error)

  defp text(bytes, :unicodeChar) do
    case :unicode.characters_to_binary(bytes, {:utf16, :big}) do
      string when is_binary(string) -> {:ok, string}
      _invalid_or_incomplete -> :error
    end
  end

  # The errors of a field, found by prepare/1, and those of a cell, found
  # with its decoder, name the field.
  defp unsupported(%Field{name: name, datatype: datatype}),
    do: {:error, "field #{inspect(name)}: the #{datatype} datatype is not supported"}

  defp invalid_null(text, %Field{name: name, datatype: datatype}),
    do:
      {:error,
       "field #{inspect(name)}: the null value #{inspect(text)} is not a valid #{datatype}"}

  defp invalid(text, %{field: %Field{name: name, datatype: datatype}}),
    do: {:error, "field #{inspect(name)}: #{inspect(text)} is not a valid #{datatype}"}

  defp doesnt_fit(text, %{field: %Field{name: name, arraysize: arraysize}}),
    do:
      {:error,
       "field #{inspect(name)}: #{inspect(text)} doesn't fit arraysize #{inspect(arraysize)}"}
end
