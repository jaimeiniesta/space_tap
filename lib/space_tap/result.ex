defmodule SpaceTAP.Result do
  @moduledoc """
  The table a query returns: its columns, in order, and its rows.

  Each row is a list with one value per column, in the same order as
  `columns`. What the values are depends on the format the query asks for
  with the `:format` option of `SpaceTAP.query/3`:

    * CSV, the default, carries no types, so every value is a string and an
      empty cell is `nil`: no IVOA standard defines how CSV represents NULL.
      CSV can't carry `fields` or `overflow`, so both are `nil`.
    * VOTable describes each column with a `SpaceTAP.Field`, whose datatype
      decides the value of each cell: an integer, a float, a boolean, a
      string, or a list for an array. A null cell is `nil`, and so is a float
      holding NaN; +Inf and -Inf are `:infinity` and `:neg_infinity`.
      `overflow` is `true` when the TAP service truncated the result at
      MAXREC or at a limit of its own (DALI 1.1 §4.4.1).

  `to_dataframe/1` turns a result into an `Explorer.DataFrame`, with the
  types of its fields.
  """

  @enforce_keys [:columns, :rows]
  defstruct [:columns, :rows, :fields, :overflow]

  @typedoc """
  The value of a cell: a string or `nil` from CSV, and any of these from
  VOTable, as the datatype and arraysize of its field say.
  """
  @type value ::
          String.t()
          | integer()
          | float()
          | boolean()
          | :infinity
          | :neg_infinity
          | nil
          | [value()]

  @typedoc """
  A result:

    * `:columns` - the column names, in order.
    * `:rows` - one list of values per row.
    * `:fields` - the description of each column, in order, from VOTable.
      `nil` from CSV.
    * `:overflow` - whether the TAP service truncated the result, from
      VOTable. `nil` from CSV.
  """
  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[value()]],
          fields: [SpaceTAP.Field.t()] | nil,
          overflow: boolean() | nil
        }

  # Explorer is an optional dependency: to_dataframe/1 checks for it when it
  # is called, so compiling SpaceTAP without it doesn't warn.
  @compile {:no_warn_undefined, [Explorer.DataFrame, Explorer.Series]}

  # The Explorer dtype of each VOTable datatype SpaceTAP reads, the same
  # width as in BINARY (VOTable 1.5 §2.1), as astropy keeps it.
  @dtypes %{
    unsignedByte: {:u, 8},
    short: {:s, 16},
    int: {:s, 32},
    long: {:s, 64},
    float: {:f, 32},
    double: {:f, 64},
    boolean: :boolean,
    char: :string,
    unicodeChar: :string
  }

  @doc """
  Turns a result into an `Explorer.DataFrame`, with one series per column,
  in the same order.

  It needs [Explorer](https://hex.pm/packages/explorer), which SpaceTAP
  doesn't install. Add it to your dependencies:

      {:explorer, "~> 0.13"}

  Each column of a VOTable result gets the dtype of its field, also when
  every cell is null or there are no rows:

  | Datatype | Dtype |
  |---|---|
  | `unsignedByte` | `{:u, 8}` |
  | `short`, `int`, `long` | `{:s, 16}`, `{:s, 32}`, `{:s, 64}` |
  | `float`, `double` | `{:f, 32}`, `{:f, 64}` |
  | `boolean` | `:boolean` |
  | `char`, `unicodeChar` | `:string` |

  An array is a `{:list, dtype}`, nested once for each dimension of its
  arraysize but the one a string takes: a `double` with arraysize `"3"` is a
  `{:list, {:f, 64}}`, and a `char` with arraysize `"10x*"` a
  `{:list, :string}`. A null is a null of the series, and `:infinity` and
  `:neg_infinity` are the infinities of a float series.

  CSV carries no types, so every column of a CSV result is a `:string`
  series: ask for VOTable with `format: :votable` to get numbers.

  A data frame can't have two columns with the same name, and a TAP service
  may send them, as in `SELECT a.ra, b.ra`. The second gets a number after
  its name, `ra2`, as PyVO names it, and `columns` keeps the names the
  service sent. The units and the other metadata of each column stay in
  `fields`, and `overflow` in the result
  ([ADR 0011](https://github.com/jaimeiniesta/space_tap/blob/main/docs/adr/0011-to-dataframe-takes-the-types-of-the-fields.md)).

  Raises `ArgumentError` when Explorer isn't installed.
  """
  @spec to_dataframe(t()) :: Explorer.DataFrame.t()
  def to_dataframe(%__MODULE__{columns: columns, rows: rows} = result) do
    unless Code.ensure_loaded?(Explorer.DataFrame) do
      raise ArgumentError,
            ~s(SpaceTAP.Result.to_dataframe/1 needs Explorer: add {:explorer, "~> 0.13"} to your dependencies)
    end

    [unique_names(columns), values(rows, length(columns)), dtypes(result)]
    |> Enum.zip_with(fn [name, values, dtype] ->
      {name, Explorer.Series.from_list(values, dtype: dtype)}
    end)
    |> Explorer.DataFrame.new()
  end

  # The values of each column, from the rows.
  defp values([], count), do: List.duplicate([], count)
  defp values(rows, _count), do: Enum.zip_with(rows, & &1)

  defp dtypes(%__MODULE__{fields: nil, columns: columns}),
    do: List.duplicate(:string, length(columns))

  defp dtypes(%__MODULE__{fields: fields}), do: Enum.map(fields, &dtype/1)

  # One list for each dimension of the arraysize (§2.2), but the first of a
  # string's, which holds its characters.
  defp dtype(%SpaceTAP.Field{datatype: datatype, arraysize: arraysize}) do
    dimensions = if arraysize, do: length(String.split(arraysize, "x")), else: 0
    lists = if datatype in [:char, :unicodeChar], do: max(dimensions - 1, 0), else: dimensions

    Enum.reduce(1..lists//1, Map.fetch!(@dtypes, datatype), fn _dimension, dtype ->
      {:list, dtype}
    end)
  end

  # PyVO reads names with astropy, which adds 2, 3 and so on to a name
  # already taken, until it is free (use_names_over_ids in
  # astropy.io.votable.tree.TableElement.to_table).
  defp unique_names(names) do
    {names, _taken} =
      Enum.map_reduce(names, MapSet.new(), fn name, taken ->
        unique = unique_name(name, name, 2, taken)
        {unique, MapSet.put(taken, unique)}
      end)

    names
  end

  defp unique_name(candidate, name, number, taken) do
    if MapSet.member?(taken, candidate),
      do: unique_name(name <> Integer.to_string(number), name, number + 1, taken),
      else: candidate
  end
end
