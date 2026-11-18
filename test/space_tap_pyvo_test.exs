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

  @pleiades """
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

  # ORDER BY makes both clients get the same rows.
  @maxrec_query "SELECT TOP 10 source_id FROM gaia.dr3lite ORDER BY source_id"

  test "matches PyVO for a Pleiades cone search on GAVO's copy of Gaia DR3" do
    Pyvo.assert_parity(@gavo_url, @pleiades)
  end

  test "matches PyVO when MAXREC limits rows on GAVO" do
    Pyvo.assert_parity(@gavo_url, @maxrec_query, maxrec: 3)
  end

  test "matches PyVO for GAVO's tables, the columns of gaia.dr3lite and its availability" do
    Pyvo.assert_metadata_parity(@gavo_url, "gaia.dr3lite")
  end

  # A job may wait in GAVO's queue for minutes.
  @tag timeout: 600_000
  test "matches PyVO for the Pleiades cone search as an async job" do
    Pyvo.assert_parity(@gavo_url, @pleiades, async: true, timeout: 300_000)
  end

  @tag timeout: 600_000
  test "matches PyVO when MAXREC limits the rows of an async job" do
    Pyvo.assert_parity(@gavo_url, @maxrec_query, async: true, maxrec: 3, timeout: 300_000)
  end
end
