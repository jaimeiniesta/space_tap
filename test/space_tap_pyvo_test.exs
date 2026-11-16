defmodule SpaceTAPPyvoTest do
  # Parity tests for GAVO, the service `mix test.release` runs against before
  # a release (docs/adr/0009-gavo-is-the-service-releases-are-tested-against.md).
  # The other services have theirs in SpaceTAPServicesPyvoTest.
  use ExUnit.Case, async: false

  alias SpaceTAP.Test.Pyvo

  @moduletag :pyvo

  if reason = Pyvo.skip_reason() do
    @moduletag skip: reason
  end

  @gavo_url "https://dc.g-vo.org/tap"

  test "matches PyVO for a Pleiades cone search on GAVO's copy of Gaia DR3" do
    adql = """
    SELECT TOP 5 source_id, ra, dec, parallax, phot_g_mean_mag
    FROM gaia.dr3lite
    WHERE CONTAINS(
      POINT('ICRS', ra, dec),
      CIRCLE('ICRS', 56.75, 24.12, 1.0)
    ) = 1
    AND parallax IS NOT NULL
    AND phot_g_mean_mag IS NOT NULL
    ORDER BY phot_g_mean_mag
    """

    Pyvo.assert_parity(@gavo_url, adql)
  end

  # ORDER BY makes both clients get the same rows.
  test "matches PyVO when MAXREC limits rows on GAVO" do
    adql = "SELECT TOP 10 source_id FROM gaia.dr3lite ORDER BY source_id"

    Pyvo.assert_parity(@gavo_url, adql, maxrec: 3)
  end
end
