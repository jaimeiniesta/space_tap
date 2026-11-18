defmodule SpaceTAP.TAPSchema do
  @moduledoc false

  # Reads the tables and the columns a TAP service publishes from
  # TAP_SCHEMA, which every TAP service must have (TAP 1.1 §4, TAP 1.0
  # §2.6), with a sync query in VOTable (ADR 0013). The query asks for
  # SELECT *: NED has no arraysize or xtype, as in TAP 1.0, so naming the
  # columns of TAP 1.1 would fail there. Each value is read by its standard
  # name in lower case, since ADQL names are case insensitive (ADQL 2.1
  # §2.1.7): the columns a service adds are left out, such as IRSA's
  # irsa_*, and a standard one it lacks is nil.
  #
  # A result marked as overflow (DALI 1.1 §4.4.1) gives its list with a
  # warning, not an error: MAST marks every result so, even one with no
  # rows, and a list cut short at a service's own limit should still show.

  require Logger

  alias SpaceTAP.{ADQL, Column, Error, HTTP, Result, Table}

  @spec tables_query(String.t() | nil) :: String.t()
  def tables_query(nil), do: "SELECT * FROM TAP_SCHEMA.tables"

  def tables_query(schema),
    do: tables_query(nil) <> " WHERE schema_name = " <> ADQL.literal(schema)

  @spec columns_query(String.t()) :: String.t()
  def columns_query(table_name),
    do: "SELECT * FROM TAP_SCHEMA.columns WHERE table_name = " <> ADQL.literal(table_name)

  # `status` is the HTTP status of the response, for a :decode_error.
  @spec tables(Result.t(), pos_integer() | nil) :: {:ok, [Table.t()]} | {:error, Error.t()}
  def tables(result, status) do
    read(result, status, "tables", "table_name", "table_index", fn row ->
      {:ok,
       %Table{
         schema: row["schema_name"],
         name: row["table_name"],
         type: row["table_type"],
         description: row["description"],
         utype: row["utype"]
       }}
    end)
  end

  @spec columns(Result.t(), pos_integer() | nil) :: {:ok, [Column.t()]} | {:error, Error.t()}
  def columns(result, status) do
    read(result, status, "columns", "column_name", "column_index", fn row ->
      with {:ok, indexed} <- flag(row, "indexed"),
           {:ok, principal} <- flag(row, "principal"),
           {:ok, std} <- flag(row, "std") do
        {:ok,
         %Column{
           name: row["column_name"],
           datatype: row["datatype"],
           arraysize: arraysize(row["arraysize"]),
           xtype: row["xtype"],
           unit: row["unit"],
           ucd: row["ucd"],
           utype: row["utype"],
           description: row["description"],
           indexed: indexed,
           principal: principal,
           std: std
         }}
      end
    end)
  end

  #####################
  # Private functions #
  #####################

  # Each row becomes a map from the lower-case name of each column to its
  # value. The rows go in the order of `index_name`, which TAP 1.1 §4.2 and
  # §4.3 give "to recommend ordering for clients", and those without one
  # last, in the order they came: TAP 1.0 has no such column, so ORDER BY
  # could fail.
  defp read(
         %Result{columns: columns, rows: rows} = result,
         status,
         table,
         name,
         index_name,
         build
       ) do
    names = Enum.map(columns, &String.downcase/1)

    if result.overflow do
      Logger.warning(
        "the TAP service marked TAP_SCHEMA.#{table} as overflow, so the list of #{table} " <>
          "may be cut short. Some services, such as MAST, mark every result so."
      )
    end

    if name in names do
      rows
      |> Enum.map(&(names |> Enum.zip(&1) |> Map.new()))
      |> Enum.sort_by(&order(&1[index_name]))
      |> build_all(build, [])
      |> case do
        {:ok, items} -> {:ok, items}
        {:error, message} -> HTTP.error(:decode_error, "TAP_SCHEMA.#{table}#{message}", status)
      end
    else
      HTTP.error(:decode_error, "TAP_SCHEMA.#{table} has no #{name} column", status)
    end
  end

  defp order(index) when is_integer(index), do: {0, index}
  defp order(_index), do: {1, 0}

  defp build_all([], _build, items), do: {:ok, Enum.reverse(items)}

  defp build_all([row | rows], build, items) do
    case build.(row) do
      {:ok, item} -> build_all(rows, build, [item | items])
      {:error, message} -> {:error, message}
    end
  end

  # The flags are "boolean values implemented as integers", 0 or 1 and
  # nothing else (TAP 1.1 §4.3). NED leaves std empty.
  defp flag(row, name) do
    case row[name] do
      value when value in [1, true] -> {:ok, true}
      value when value in [0, false] -> {:ok, false}
      nil -> {:ok, nil}
      value -> {:error, ": expected #{name} to be 0 or 1, got: #{inspect(value)}"}
    end
  end

  # IRSA declares arraysize as an int.
  defp arraysize(size) when is_integer(size), do: Integer.to_string(size)
  defp arraysize(size), do: size
end
