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

  test "answers the query as its fixture does",
       %{url: url, result: {adql, _expected}} = service do
    assert_answer(url, adql, [], Services.csv_result(service))
  end

  test "answers the query with VOTable as its fixture does", %{url: url, result: {adql, expected}} do
    assert_answer(url, adql, [format: :votable], expected)
  end

  test "answers invalid ADQL as its fixture does", %{url: url, syntax_error: {adql, expected}} do
    assert_answer(url, adql, [], expected)
  end

  #####################
  # Private functions #
  #####################

  defp assert_answer(url, adql, opts, expected) do
    response = SpaceTAP.query(url, adql, [req_options: Services.req_options()] ++ opts)

    case expected do
      {:ok, columns, row_count} ->
        assert {:ok, %Result{columns: ^columns, rows: rows}} = response
        assert length(rows) == row_count

      {:error, type, status, message} ->
        assert {:error, %Error{type: ^type, status: ^status, message: actual}} = response
        assert actual =~ message
    end
  end
end
