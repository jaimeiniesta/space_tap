defmodule SpaceTAPIntegrationTest do
  # Queries to GAVO, the service `mix test.release` runs against before a
  # release (docs/adr/0009-gavo-is-the-service-releases-are-tested-against.md),
  # on its copy of Gaia DR3, sync and as async jobs. The other services have
  # theirs in SpaceTAPServicesLiveTest.
  use ExUnit.Case, async: false

  alias SpaceTAP.{Error, Job, Result}

  @moduletag :integration

  @service_url "https://dc.g-vo.org/tap"

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

  test "runs a Pleiades cone search" do
    assert {:ok, %Result{columns: columns, rows: rows}} = SpaceTAP.query(@service_url, @pleiades)

    assert columns == ["source_id", "ra", "dec", "parallax", "phot_g_mean_mag"]
    assert length(rows) == 5
  end

  test "reads the VOTable with typed values" do
    assert {:ok, %Result{columns: columns, rows: rows, fields: fields, overflow: false}} =
             SpaceTAP.query(@service_url, @pleiades, format: :votable)

    assert columns == ["source_id", "ra", "dec", "parallax", "phot_g_mean_mag"]
    # gaia.dr3lite declares parallax a float, where Gaia's archive has a double.
    assert Enum.map(fields, & &1.datatype) == [:long, :double, :double, :float, :float]
    assert length(rows) == 5

    for [source_id | values] <- rows do
      assert is_integer(source_id)
      assert Enum.all?(values, &is_float/1)
    end
  end

  # DALI 1.1 §3.4.4: "If the size of the result exceeds the resulting limit,
  # the service must only return the requested number of rows." GAVO sends
  # one row more, and SpaceTAP returns the rows the service sends.
  test "sets overflow when MAXREC cuts the result, with the row GAVO adds" do
    adql = "SELECT TOP 10 source_id FROM gaia.dr3lite ORDER BY source_id"

    assert {:ok, %Result{rows: rows, overflow: true}} =
             SpaceTAP.query(@service_url, adql, format: :votable, maxrec: 3)

    assert length(rows) == 4
  end

  test "sends MAXREC with CSV, and gets the row GAVO adds" do
    adql = "SELECT TOP 10 source_id FROM gaia.dr3lite ORDER BY source_id"

    assert {:ok, %Result{columns: ["source_id"], rows: rows}} =
             SpaceTAP.query(@service_url, adql, maxrec: 3)

    assert length(rows) == 4
  end

  # DALI 1.1 §3.4.4 says MAXREC=0 asks for "metadata, no results, and an
  # overflow indicator". GAVO sends the overflow indicator and one row.
  test "returns the columns and overflow when MAXREC is zero, with the row GAVO adds" do
    adql = "SELECT TOP 3 source_id, ra, dec FROM gaia.dr3lite"

    assert {:ok, %Result{columns: ["source_id", "ra", "dec"], rows: rows, overflow: true}} =
             SpaceTAP.query(@service_url, adql, format: :votable, maxrec: 0)

    assert length(rows) == 1
  end

  # DaCHS sends its error documents with HTTP 500.
  test "returns a service error for invalid ADQL" do
    adql = "SELEC TOP 3 source_id FROM gaia.dr3lite"

    assert {:error, %Error{type: :service_error, status: 500, message: message}} =
             SpaceTAP.query(@service_url, adql)

    assert message =~ "Could not parse your query"
  end

  describe "async queries" do
    # A job may wait in GAVO's queue for minutes, and a :timeout deletes it
    # before ExUnit gives up on the test.
    @describetag timeout: 600_000

    @async_options [timeout: 300_000]

    test "runs the Pleiades cone search as a job, with typed values" do
      assert {:ok, %Result{columns: columns, rows: rows, fields: fields, overflow: false}} =
               SpaceTAP.async_query(@service_url, @pleiades, [format: :votable] ++ @async_options)

      assert columns == ["source_id", "ra", "dec", "parallax", "phot_g_mean_mag"]
      assert Enum.map(fields, & &1.datatype) == [:long, :double, :double, :float, :float]
      assert length(rows) == 5
    end

    test "runs it as a job with CSV" do
      assert {:ok, %Result{columns: ["source_id" | _columns], rows: rows, fields: nil}} =
               SpaceTAP.async_query(@service_url, @pleiades, @async_options)

      assert length(rows) == 5
      assert Enum.all?(List.flatten(rows), &is_binary/1)
    end

    test "sets overflow when MAXREC cuts the result of a job, with the row GAVO adds" do
      adql = "SELECT TOP 10 source_id FROM gaia.dr3lite ORDER BY source_id"
      options = [format: :votable, maxrec: 3] ++ @async_options

      assert {:ok, %Result{rows: rows, overflow: true}} =
               SpaceTAP.async_query(@service_url, adql, options)

      assert length(rows) == 4
    end

    # The job ends in ERROR, and the message comes from its error summary.
    test "returns a service error for a job with invalid ADQL" do
      adql = "SELEC TOP 3 source_id FROM gaia.dr3lite"

      assert {:error, %Error{type: :service_error, status: nil, message: message}} =
               SpaceTAP.async_query(@service_url, adql, @async_options)

      assert message =~ "the job is ERROR: Field query: Could not parse your query"
    end

    test "submits, waits for, reads and deletes a job, one step at a time" do
      assert {:ok, %Job{url: url, format: :votable} = job} =
               Job.submit(@service_url, @pleiades, format: :votable)

      # GAVO runs its jobs under another path than the service URL.
      assert url =~ ~r{^https://dc\.g-vo\.org/__system__/tap/run/async/}

      assert {:ok, %Job{phase: :completed, result_url: result_url} = job} =
               Job.wait(job, @async_options)

      # GAVO lists http:// URLs, which result/2 reads with https://.
      assert result_url =~ ~r{^http://dc\.g-vo\.org/}
      assert {:ok, %Result{rows: rows}} = Job.result(job)
      assert length(rows) == 5

      assert {:ok, %Job{phase: :completed}} = Job.get(url, format: :votable)
      assert Job.delete(job) == :ok

      # DaCHS answers 404 with an error document for a job it no longer has.
      assert {:error, %Error{type: :service_error, status: 404}} = Job.get(url)
    end
  end
end
