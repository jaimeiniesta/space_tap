defmodule SpaceTAPServicesPyvoTest do
  # Parity tests for the services the services tests cover, with the query of
  # each one's result fixture. MAST is left out: it answers with VOTable,
  # which SpaceTAP doesn't read yet. Like the services tests, a failure is a
  # reason to look into that service, not to hold a release, so they are
  # tagged :services rather than :pyvo and run with `mix test.services`.
  alias SpaceTAP.Test.{Pyvo, Services}

  # The alias comes first because parameterize reads it.
  use ExUnit.Case, async: true, parameterize: Services.with_result()

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 180_000

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  test "matches PyVO for the query of its fixture", %{url: url, result: {adql, _expected}} do
    Pyvo.assert_parity(url, adql, req_options: Services.req_options())
  end
end
