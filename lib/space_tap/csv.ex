defmodule SpaceTAP.CSV do
  @moduledoc false

  # Reads the CSV body of a successful sync query. TAP 1.1 §3.2 puts the column
  # names in the first row and defers the rest of the format to RFC 4180.

  alias NimbleCSV.RFC4180, as: Parser
  alias SpaceTAP.Result

  @spec parse(binary()) :: {:ok, Result.t()} | {:error, String.t()}
  def parse(body) when is_binary(body) do
    case Parser.parse_string(body, skip_headers: false) do
      [] -> {:error, "empty CSV body, expected a header row with the column names"}
      [columns | rows] -> build(columns, rows)
    end
  rescue
    error in NimbleCSV.ParseError -> {:error, "invalid CSV: " <> Exception.message(error)}
  end

  # RFC 4180 §2.4: every row has the same number of fields.
  defp build(columns, rows) do
    width = length(columns)

    case Enum.find_index(rows, &(length(&1) != width)) do
      nil ->
        {:ok, %Result{columns: columns, rows: Enum.map(rows, &empty_to_nil/1)}}

      index ->
        fields = rows |> Enum.at(index) |> length()
        {:error, "data row #{index + 1} has #{fields} fields, expected #{width}"}
    end
  end

  # No IVOA standard defines NULL in CSV; Gaia sends an empty field.
  defp empty_to_nil(row), do: Enum.map(row, &if(&1 == "", do: nil, else: &1))
end
