defmodule SpaceTAPPyvoTest do
  # Parity tests for Gaia and the NASA Exoplanet Archive, which `mix test.all`
  # runs before a release. The other services have theirs in
  # SpaceTAPServicesPyvoTest.
  use ExUnit.Case, async: false

  alias SpaceTAP.Test.Pyvo

  @moduletag :pyvo

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  @gaia_url "https://gea.esac.esa.int/tap-server/tap"
  @exoplanet_archive_url "https://exoplanetarchive.ipac.caltech.edu/TAP"

  test "matches pyvo for a Pleiades cone search on Gaia" do
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

    Pyvo.assert_parity(@gaia_url, adql)
  end

  test "matches pyvo when MAXREC limits rows on Gaia" do
    adql = "SELECT TOP 10 source_id FROM gaiadr3.gaia_source"

    Pyvo.assert_parity(@gaia_url, adql, maxrec: 3)
  end

  test "matches pyvo for the NASA Exoplanet Archive's CSV, which it sends as text/plain" do
    adql = "SELECT TOP 3 pl_name, disc_year FROM ps"

    Pyvo.assert_parity(@exoplanet_archive_url, adql)
  end
end
