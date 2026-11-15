defmodule SpaceTAPPyvoTest do
  # Parity tests for Gaia and the NASA Exoplanet Archive, which
  # `mix test.release` runs before a release. The other services have theirs
  # in SpaceTAPServicesPyvoTest.
  use ExUnit.Case, async: false

  alias SpaceTAP.Test.Pyvo

  @moduletag :pyvo

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  @gaia_url "https://gea.esac.esa.int/tap-server/tap"
  @exoplanet_archive_url "https://exoplanetarchive.ipac.caltech.edu/TAP"

  test "matches PyVO for a Pleiades cone search on Gaia" do
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

  # ORDER BY makes both clients get the same 3 rows.
  test "matches PyVO when MAXREC limits rows on Gaia" do
    adql = "SELECT TOP 10 source_id FROM gaiadr3.gaia_source ORDER BY source_id"

    Pyvo.assert_parity(@gaia_url, adql, maxrec: 3)
  end

  # The archive applies TOP before ORDER BY, so the query names its planets.
  # default_flag = 1 picks one row of parameters for each.
  test "matches PyVO for the NASA Exoplanet Archive, whose CSV comes as text/plain" do
    adql = """
    SELECT pl_name, disc_year FROM ps
    WHERE default_flag = 1 AND pl_name IN ('WASP-39 b', 'GJ 436 b', 'HAT-P-1 b')
    """

    Pyvo.assert_parity(@exoplanet_archive_url, adql)
  end
end
