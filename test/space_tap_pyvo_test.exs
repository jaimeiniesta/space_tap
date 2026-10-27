defmodule SpaceTAPPyvoTest do
  use ExUnit.Case, async: false

  alias SpaceTAP.Result

  @moduletag :pyvo

  @service_url "https://gea.esac.esa.int/tap-server/tap"
  @runner Path.expand("support/pyvo_query.py", __DIR__)
  @uv System.find_executable("uv")

  if is_nil(@uv) and is_nil(System.get_env("CI")) do
    @moduletag skip: "`uv` is required to run the pyvo parity tests"
  end

  test "matches pyvo for a Pleiades cone search" do
    adql = """
    SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag
    FROM gaiadr3.gaia_source
    WHERE CONTAINS(
      POINT('ICRS', ra, dec),
      CIRCLE('ICRS', 56.75, 24.12, 1.0)
    ) = 1
    AND parallax IS NOT NULL
    AND phot_g_mean_mag IS NOT NULL
    ORDER BY phot_g_mean_mag
    """

    assert_parity(adql)
  end

  test "matches pyvo when MAXREC limits rows" do
    adql = "SELECT TOP 10 source_id FROM gaiadr3.gaia_source"

    assert_parity(adql, maxrec: 3)
  end

  #####################
  # Private functions #
  #####################

  defp assert_parity(adql, opts \\ []) do
    assert {:ok, %Result{columns: columns, rows: rows}} =
             SpaceTAP.query(@service_url, adql, opts)

    assert %{"columns" => pyvo_columns, "row_count" => pyvo_row_count} =
             pyvo_query(adql, opts)

    assert pyvo_columns == columns
    assert pyvo_row_count == length(rows)
  end

  defp pyvo_query(adql, opts) do
    uv = @uv || flunk("`uv` is required to run the pyvo parity tests")
    args = ["run", "--quiet", @runner, @service_url, adql] ++ maxrec_arg(opts)

    case System.cmd(uv, args) do
      {output, 0} ->
        assert {:ok, result} = JSON.decode(output)
        result

      {output, status} ->
        flunk("pyvo runner exited with status #{status}: #{String.trim(output)}")
    end
  end

  defp maxrec_arg(opts) do
    case Keyword.fetch(opts, :maxrec) do
      {:ok, maxrec} -> [Integer.to_string(maxrec)]
      :error -> []
    end
  end
end
