defmodule SpaceTAP.VOTable.Value do
  @moduledoc false

  # Turns the text of one TABLEDATA cell into an Elixir value, following the
  # datatype and arraysize of its field (VOTable 1.5 §5.1 and §6) and ADR 0007.

  alias SpaceTAP.Field

  # The white space of §5.1, which matters only in strings.
  @whitespace [" ", "\t", "\n", "\r"]

  # The bits of each integer datatype, which also give the number of
  # hexadigits it may have (§6).
  @integer_bits %{unsignedByte: 8, short: 16, int: 32, long: 64}

  @spec parse_text(String.t(), Field.t()) :: {:ok, term()} | {:error, String.t()}

  # No service in the README's Compatibility table has sent these, and a
  # complex number would need an Elixir value ADR 0007 doesn't choose.
  def parse_text(_text, %Field{datatype: datatype} = field)
      when datatype in [:bit, :floatComplex, :doubleComplex] do
    {:error, "field #{inspect(field.name)}: the #{datatype} datatype is not supported"}
  end

  def parse_text("", %Field{}), do: {:ok, nil}

  # A string is an array of characters, written with no separator and with
  # its white space (§5.1). A fixed arraysize is the most characters it holds,
  # since §5.1 writes Apple in an arraysize of 10. A char is ASCII (§6), and a
  # unicodeChar is counted in characters, the UCS-2 units of BINARY.
  def parse_text(text, %Field{datatype: datatype} = field)
      when datatype in [:char, :unicodeChar] do
    cond do
      datatype == :char and not ascii?(text) -> invalid(text, field)
      field.arraysize == nil and characters(text) != 1 -> invalid(text, field)
      field.arraysize == nil -> {:ok, unless_null(text, field.null)}
      true -> with {:ok, shape} <- shape(field), do: string(text, shape, field)
    end
  end

  def parse_text(text, %Field{arraysize: nil} = field) do
    case String.split(text, @whitespace, trim: true) do
      [] ->
        {:ok, nil}

      [token] ->
        with {:ok, null} <- null(field),
             {:ok, [value]} <- elements([token], field, null, []),
             do: {:ok, value}

      _tokens ->
        invalid(text, field)
    end
  end

  # The numbers of an array are separated by white space (§5.1). An array
  # with none is nil, since TABLEDATA writes it like a null (§5.5).
  def parse_text(text, %Field{} = field) do
    with {:ok, shape} <- shape(field),
         {:ok, null} <- null(field) do
      case String.split(text, @whitespace, trim: true) do
        [] -> {:ok, nil}
        tokens -> array(tokens, shape, null, text, field)
      end
    end
  end

  #####################
  # Private functions #
  #####################

  defp array(tokens, {fixed, _last} = shape, null, text, field) do
    if fits?(length(tokens), shape) do
      with {:ok, values} <- elements(tokens, field, null, []), do: {:ok, nest(values, fixed)}
    else
      doesnt_fit(text, field)
    end
  end

  # A fixed size is the most characters a string holds, so "Apple" fits in
  # 10, but the strings of a multidimensional array fill the first dimension:
  # without a separator, that is the only way to tell where each one ends.
  # §4.7 says the null value is never an array, but a string is an array of
  # characters, so the null value of a string field is compared with each
  # whole string.
  defp string(text, {[], last}, field) do
    last = if is_integer(last), do: {:at_most, last}, else: last

    if fits_last?(characters(text), last),
      do: {:ok, unless_null(text, field.null)},
      else: doesnt_fit(text, field)
  end

  defp string(text, {[size | fixed], _last} = shape, field) do
    characters = String.codepoints(text)

    if fits?(length(characters), shape) do
      strings =
        characters
        |> Enum.chunk_every(size)
        |> Enum.map(&unless_null(Enum.join(&1), field.null))

      {:ok, nest(strings, fixed)}
    else
      doesnt_fit(text, field)
    end
  end

  # The null value is one TABLEDATA value of the datatype (§4.7). It is read
  # like a cell, so 0x8000 and -32768 are the same null of a short. A field
  # without one gets nil, which turns nothing into nil.
  defp null(%Field{null: nil}), do: {:ok, nil}

  defp null(%Field{null: text, datatype: datatype} = field) do
    with [token] <- String.split(text, @whitespace, trim: true),
         {:ok, value} <- element(token, datatype) do
      {:ok, value}
    else
      _other ->
        {:error,
         "field #{inspect(field.name)}: the null value #{inspect(text)} is not a valid #{datatype}"}
    end
  end

  defp unless_null(value, null), do: if(value == null, do: nil, else: value)

  # Each element of an array is checked against the null value, the only way
  # to mark one of them as null (§5.5).
  defp elements([], _field, _null, values), do: {:ok, Enum.reverse(values)}

  defp elements([token | tokens], field, null, values) do
    case element(token, field.datatype) do
      {:ok, value} -> elements(tokens, field, null, [unless_null(value, null) | values])
      :error -> invalid(token, field)
    end
  end

  # The first dimension changes fastest (§2.2), so it makes the innermost lists.
  defp nest(values, []), do: values
  defp nest(values, [size | fixed]), do: values |> Enum.chunk_every(size) |> nest(fixed)

  # §2.2: dimensions separated by "x", the first changing fastest, and only
  # the last one variable: "N*" holds up to N elements, "*" any number. The
  # shape is the list of fixed dimensions and the last one.
  defp shape(%Field{arraysize: arraysize} = field) do
    {fixed, [last]} = arraysize |> String.split("x") |> Enum.split(-1)

    with {:ok, fixed} <- dimensions(fixed),
         {:ok, last} <- last_dimension(last) do
      {:ok, {fixed, last}}
    else
      :error ->
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
    with {digits, ""} when digits != "" <- split_digits(text),
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

  defp characters(text), do: text |> String.to_charlist() |> length()

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
  # float and 1 to 3 in a double. Float.parse/1 gets the number with a zero
  # before and after the point, a form it always reads, and fails only when
  # the number is beyond the largest double.
  defp decimal(text) do
    {sign, text} = split_sign(text)
    {integer, text} = split_digits(text)
    {fraction, text} = split_fraction(text)

    case {integer <> fraction, exponent(text)} do
      {"", _exponent} -> :error
      {_digits, :error} -> :error
      {_digits, {:ok, exponent}} -> to_float("#{sign}0#{integer}.#{fraction}0e#{exponent}")
    end
  end

  defp split_sign("+" <> rest), do: {"+", rest}
  defp split_sign("-" <> rest), do: {"-", rest}
  defp split_sign(text), do: {"", text}

  defp split_digits(<<digit, rest::binary>>) when digit in ?0..?9 do
    {digits, rest} = split_digits(rest)
    {<<digit, digits::binary>>, rest}
  end

  defp split_digits(text), do: {"", text}

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

  defp to_float(text) do
    case Float.parse(text) do
      {double, ""} -> {:ok, double}
      _beyond_the_largest_double -> :error
    end
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

  defp invalid(text, %Field{name: name, datatype: datatype}) do
    {:error, "field #{inspect(name)}: #{inspect(text)} is not a valid #{datatype}"}
  end

  defp doesnt_fit(text, %Field{name: name, arraysize: arraysize}) do
    {:error,
     "field #{inspect(name)}: #{inspect(text)} doesn't fit arraysize #{inspect(arraysize)}"}
  end
end
