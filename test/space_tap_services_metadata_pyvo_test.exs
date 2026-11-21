defmodule SpaceTAPServicesMetadataPyvoTest do
  # Parity tests for the tables, the columns and the availability of the
  # services whose TAP_SCHEMA was checked, against PyVO, which reads tables
  # and columns from the VOSI /tables resource where SpaceTAP reads
  # TAP_SCHEMA. Like the other services tests, they run with
  # `mix test.services`. The tables of a service with a `tables_error` aren't
  # compared.
  alias SpaceTAP.Test.{Pyvo, Services}

  # The alias comes first because parameterize reads it.
  use ExUnit.Case, async: true, parameterize: Services.with_metadata()

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 300_000

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  test "matches PyVO for its tables, the columns of the table of its fixtures and its availability",
       %{url: url, metadata: {_schema, table, _column}} = service do
    Pyvo.assert_metadata_parity(url, table,
      tables: not Map.has_key?(service, :tables_error),
      req_options: Services.req_options()
    )
  end
end
