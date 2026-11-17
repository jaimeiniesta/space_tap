defmodule SpaceTAPServicesAsyncPyvoTest do
  # Parity tests for the services the services tests cover, with the query of
  # each one's result fixture run as an async job in both clients. Tagged
  # :services, like SpaceTAPServicesPyvoTest, and run with
  # `mix test.services`.
  #
  # NED is left out: PyVO 1.9.1 can't read its job documents, whose times
  # carry a UTC offset (test/space_tap_fixtures_pyvo_test.exs), and fails
  # after creating the job, which it can't delete then, and which NED never
  # destroys. SpaceTAPServicesLiveTest runs NED's query as a job.
  alias SpaceTAP.Test.{Pyvo, Services}

  # The alias comes first because parameterize reads it.
  use ExUnit.Case,
    async: true,
    parameterize: Enum.reject(Services.all(), &(&1.service == "NED"))

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 600_000

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  test "matches PyVO for the query of its fixture as an async job",
       %{url: url, result: {adql, _expected}} = service do
    csv? = match?({:ok, _columns, _row_count}, Services.async_csv_result(service))

    Pyvo.assert_parity(url, adql,
      async: true,
      timeout: 300_000,
      req_options: Services.req_options(),
      csv: csv?
    )
  end
end
