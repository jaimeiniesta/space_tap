defmodule SpaceTAP.Test.Pyvo do
  @moduledoc false

  # Runs a query through PyVO, an Astropy-affiliated Python client for IVOA
  # services, and compares its result with SpaceTAP's. pyvo_query.py, next to
  # this file, is a PEP 723 script that pins PyVO and prints JSON; `uv run`
  # installs what it needs. Without `uv`, parity tests skip locally and fail
  # when CI is set.
  #
  # PyVO doesn't ask for CSV: it reads the VOTable the service sends by
  # default. So a parity test also checks that the CSV header SpaceTAP reads
  # names the same columns as the VOTable fields PyVO reads. Until SpaceTAP
  # reads VOTable with types (0.2), it compares column names and row counts.

  import ExUnit.Assertions

  alias SpaceTAP.Result

  @runner Path.expand("pyvo_query.py", __DIR__)

  # For `@moduletag skip:` in the parity tests.
  @spec skip_reason() :: String.t() | nil
  def skip_reason do
    if is_nil(System.find_executable("uv")) and is_nil(System.get_env("CI")) do
      "`uv` is required to run the PyVO parity tests"
    end
  end

  # `opts` go to SpaceTAP.query/3; PyVO gets `:maxrec` only.
  @spec assert_parity(String.t(), String.t(), keyword()) :: true
  def assert_parity(service_url, adql, opts \\ []) do
    assert {:ok, %Result{columns: columns, rows: rows}} =
             SpaceTAP.query(service_url, adql, opts)

    assert %{"columns" => pyvo_columns, "row_count" => pyvo_row_count} =
             query(service_url, adql, opts)

    assert pyvo_columns == columns
    assert pyvo_row_count == length(rows)
  end

  #####################
  # Private functions #
  #####################

  defp query(service_url, adql, opts) do
    uv = System.find_executable("uv") || flunk("`uv` is required to run the PyVO parity tests")
    args = ["run", "--quiet", @runner, service_url, adql] ++ maxrec_arg(opts)

    case System.cmd(uv, args) do
      {output, 0} ->
        assert {:ok, result} = JSON.decode(output)
        result

      {output, status} ->
        flunk("PyVO runner exited with status #{status}: #{String.trim(output)}")
    end
  end

  defp maxrec_arg(opts) do
    case Keyword.fetch(opts, :maxrec) do
      {:ok, maxrec} -> [Integer.to_string(maxrec)]
      :error -> []
    end
  end
end
