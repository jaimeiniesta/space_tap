defmodule SpaceTAP.ADQL do
  @moduledoc """
  Helpers to write ADQL, the query language of TAP.

  ADQL has no bound parameters: a value goes into a query as text, and the
  TAP service parses it. `literal/1` writes an Elixir value as an ADQL
  literal, so that a string with a quote in it, or a float with an exponent,
  reaches the service as the value it was:

      iex> name = "Barnard's Star"
      iex> "SELECT main_id, ra, dec FROM basic WHERE main_id = " <> SpaceTAP.ADQL.literal(name)
      "SELECT main_id, ra, dec FROM basic WHERE main_id = 'Barnard''s Star'"

  `cone/5` writes the condition of a cone search, the rows whose position
  falls within a circle on the sky:

      iex> "SELECT TOP 10 source_id FROM gaiadr3.gaia_source WHERE " <>
      ...>   SpaceTAP.ADQL.cone("ra", "dec", 56.75, 24.12, 1.0)
      "SELECT TOP 10 source_id FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1"

  Both return text: they don't check the query or send it
  (`docs/adr/0012-adql-helpers-write-plain-text.md`).
  """

  @typedoc """
  A value `literal/1` writes: a string, a number, `nil`, or a list of them
  for `IN`.
  """
  @type value :: String.t() | number() | nil | [String.t() | number() | nil]

  @doc """
  Writes a value as an ADQL literal (ADQL 2.1 §2.1.8).

    * A string goes in single quotes, with each single quote inside it
      doubled.
    * An integer is written in decimal, and a float with an uppercase `E`
      before its exponent, as the grammar writes it.
    * `nil` is `NULL`.
    * A list is the literals of its values, in parentheses and separated by
      commas, for `IN`.

  ADQL has no literal for an infinity, NaN or a boolean, so `:infinity`,
  `:neg_infinity`, `true`, `false` and any other value raise
  `ArgumentError`, and so does an empty list, since `IN ()` isn't valid
  ADQL, or a list inside a list.

  ## Examples

      iex> SpaceTAP.ADQL.literal("Barnard's Star")
      "'Barnard''s Star'"

      iex> SpaceTAP.ADQL.literal(66529975427235712)
      "66529975427235712"

      iex> SpaceTAP.ADQL.literal(1.0e-5)
      "1.0E-5"

      iex> SpaceTAP.ADQL.literal(nil)
      "NULL"

      iex> SpaceTAP.ADQL.literal(["WASP-39 b", "GJ 436 b"])
      "('WASP-39 b', 'GJ 436 b')"
  """
  @spec literal(value()) :: String.t()
  def literal([]),
    do: raise(ArgumentError, "ADQL has no literal for an empty list: IN needs at least one value")

  def literal(values) when is_list(values),
    do: "(" <> Enum.map_join(values, ", ", &scalar/1) <> ")"

  def literal(value), do: scalar(value)

  @doc """
  Writes the condition of a cone search: the rows whose position, in the
  columns `ra_column` and `dec_column`, falls within `radius` degrees of the
  point at right ascension `ra` and declination `dec`, in degrees.

  The condition is `CONTAINS(POINT(...), CIRCLE(...)) = 1` (ADQL 2.1
  §4.2.12, §4.2.18, §4.2.11). ADQL 2.1 §4.2.7 prefers
  `DISTANCE(...) <= radius`, but services such as the NASA Exoplanet
  Archive, KOA, CADC and MAST don't declare `DISTANCE`. Each geometry starts
  with the coordinate system, `'ICRS'`: ADQL 2.1 made that argument optional
  and deprecated it (§4.2.5), but ADQL 2.0, the only version many services
  declare, requires it. So the condition works with both versions.

  The columns are inserted as given, so they can be expressions such as
  `g.ra`, and must never come from user input. The center and the radius
  are written with `literal/1`; anything else than a number raises
  `ArgumentError`. Their ranges aren't checked: the service decides.

  ## Examples

      iex> SpaceTAP.ADQL.cone("ra", "dec", 56.75, 24.12, 1.0)
      "CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1"
  """
  @spec cone(String.t(), String.t(), number(), number(), number()) :: String.t()
  def cone(ra_column, dec_column, ra, dec, radius) do
    [ra_column, dec_column] = Enum.map([ra_column, dec_column], &column!/1)
    [ra, dec, radius] = Enum.map([ra, dec, radius], &number!/1)

    "CONTAINS(POINT('ICRS', #{ra_column}, #{dec_column}), " <>
      "CIRCLE('ICRS', #{ra}, #{dec}, #{radius})) = 1"
  end

  #####################
  # Private functions #
  #####################

  defp scalar(value) when is_binary(value), do: "'" <> String.replace(value, "'", "''") <> "'"
  defp scalar(value) when is_integer(value), do: Integer.to_string(value)
  defp scalar(value) when is_float(value), do: value |> Float.to_string() |> String.upcase()
  defp scalar(nil), do: "NULL"

  defp scalar(value),
    do: raise(ArgumentError, "ADQL has no literal for #{inspect(value)}")

  defp column!(column) when is_binary(column), do: column

  defp column!(column),
    do: raise(ArgumentError, "expected the column as a string, got: #{inspect(column)}")

  defp number!(number) when is_number(number), do: literal(number)
  defp number!(other), do: raise(ArgumentError, "expected a number, got: #{inspect(other)}")
end
