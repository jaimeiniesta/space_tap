defmodule SpaceTAPServicesMetadataTest do
  # The tables and columns of the services in the README's Compatibility
  # table whose TAP_SCHEMA was checked: the schema and the table of their
  # TAP_SCHEMA fixtures, and a column of that table. Like the other services
  # tests, a failure is a reason to look into that service, so they run with
  # `mix test.services`. MAST marks every result as overflow, so its lists
  # come with a warning, which :capture_log keeps out of the output.
  alias SpaceTAP.{Column, Table}
  alias SpaceTAP.Test.Services

  # The alias comes first because parameterize reads it.
  use ExUnit.Case, async: true, parameterize: Services.with_metadata()

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 180_000

  test "lists the table of its fixtures among the tables of its schema",
       %{url: url, metadata: {schema, table, _column}} do
    assert {:ok, tables} =
             SpaceTAP.tables(url, schema: schema, req_options: Services.req_options())

    assert Enum.all?(tables, &match?(%Table{schema: ^schema}, &1))
    assert table in Enum.map(tables, & &1.name)
  end

  test "lists the columns of that table", %{url: url, metadata: {_schema, table, column}} do
    assert {:ok, columns} = SpaceTAP.columns(url, table, req_options: Services.req_options())

    assert %Column{} = Enum.find(columns, &(&1.name == column))
  end
end
