defmodule SpaceTAPIntegrationTest do
  use ExUnit.Case, async: false

  alias SpaceTAP.{Error, Result}

  @moduletag :integration

  @service_url "https://gea.esac.esa.int/tap-server/tap"

  test "runs a Pleiades cone search" do
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

    assert {:ok, %Result{columns: columns, rows: rows}} =
             SpaceTAP.query(@service_url, adql)

    assert columns == [
             "source_id",
             "designation",
             "ra",
             "dec",
             "parallax",
             "phot_g_mean_mag"
           ]

    assert length(rows) == 5
  end

  test "returns a service error for invalid ADQL" do
    adql = "SELEC TOP 3 source_id FROM gaiadr3.gaia_source"

    assert {:error, %Error{type: :service_error, status: 400, message: message}} =
             SpaceTAP.query(@service_url, adql)

    assert message =~ "Cannot parse query 'SELEC TOP 3 source_id"
  end

  test "returns columns and no rows when MAXREC is zero" do
    adql = "SELECT TOP 3 source_id, ra, dec FROM gaiadr3.gaia_source"

    # DALI 1.1 §3.4.4 defines MAXREC=0 as a metadata-only request.
    assert {:ok, %Result{columns: ["source_id", "ra", "dec"], rows: []}} =
             SpaceTAP.query(@service_url, adql, maxrec: 0)
  end

  test "limits rows to MAXREC" do
    adql = "SELECT TOP 10 source_id FROM gaiadr3.gaia_source"

    assert {:ok, %Result{columns: ["source_id"], rows: rows}} =
             SpaceTAP.query(@service_url, adql, maxrec: 3)

    assert length(rows) == 3
  end

  test "reads the NASA Exoplanet Archive's CSV, which it sends as text/plain" do
    adql = "SELECT TOP 3 pl_name, disc_year FROM ps"

    assert {:ok, %Result{columns: ["pl_name", "disc_year"], rows: rows}} =
             SpaceTAP.query("https://exoplanetarchive.ipac.caltech.edu/TAP", adql)

    assert length(rows) == 3
  end

  test "returns the NASA Exoplanet Archive's error document as a service error" do
    adql = "SELEC TOP 3 table_name FROM TAP_SCHEMA.tables"

    assert {:error, %Error{type: :service_error, status: 400, message: message}} =
             SpaceTAP.query("https://exoplanetarchive.ipac.caltech.edu/TAP", adql)

    assert message =~ "Query is not a SELECT statemement."
  end
end
