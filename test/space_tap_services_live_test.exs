defmodule SpaceTAPServicesLiveTest do
  # The services in the README's Compatibility table other than Gaia and the
  # NASA Exoplanet Archive, which the integration tests cover. Each one gets
  # the queries of its fixtures, to check that it still answers the way they
  # say. Some are slow, and a failure is a reason to look into that service,
  # not to hold a release, so `mix test.release` leaves them out: run them
  # with `mix test.services`. Parameters run concurrently, so the services are
  # queried in parallel and each one gets one request at a time.
  alias SpaceTAP.{Error, Result}
  alias SpaceTAP.Test.Services

  # The alias comes first because parameterize reads it.
  use ExUnit.Case, async: true, parameterize: Services.all()

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 180_000

  test "answers the query as its fixture does", %{url: url, result: result} do
    assert_answer(url, result)
  end

  test "answers invalid ADQL as its fixture does", %{url: url, syntax_error: syntax_error} do
    assert_answer(url, syntax_error)
  end

  #####################
  # Private functions #
  #####################

  defp assert_answer(url, {adql, expected}) do
    response = SpaceTAP.query(url, adql, req_options: Services.req_options())

    case expected do
      {:ok, columns} ->
        assert {:ok, %Result{columns: ^columns, rows: rows}} = response
        assert length(rows) == 5

      {:error, type, status, message} ->
        assert {:error, %Error{type: ^type, status: ^status, message: actual}} = response
        assert actual =~ message
    end
  end
end
