defmodule SpaceTAPServicesLiveTest do
  # The services in the README's Compatibility table other than Gaia and the
  # NASA Exoplanet Archive, which the integration tests cover. Each one gets
  # the queries of its fixtures, to check that it still answers the way they
  # say. Some are slow, and a failure is a reason to look into that service,
  # not to hold a release, so `mix test.all` leaves them out: run them with
  # `mix test.services`. Parameters run concurrently, so the services are
  # queried in parallel and each one gets one request at a time.

  # {adql, expected} pairs, with the queries of each service's fixtures. A
  # result expects these columns and 5 rows; an error expects its type, status
  # and a part of its message that the service is unlikely to reword.
  @services [
    %{
      service: "GAVO",
      url: "https://dc.g-vo.org/tap",
      result:
        {"SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 5",
         {:ok, ["hipno", "ra", "dec", "vmag", "parallax", "SpType"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM tap_schema.tables",
         {:error, :service_error, 500, "Field query: Could not parse your query: Expected SELECT"}}
    },
    %{
      service: "IRSA",
      url: "https://irsa.ipac.caltech.edu/TAP",
      result:
        {"SELECT TOP 5 table_name, column_name, datatype, unit, description FROM TAP_SCHEMA.columns WHERE table_name = 'fp_psc'",
         {:ok, ["table_name", "column_name", "datatype", "unit", "description"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 200,
          "UsageFault: BAD_REQUEST: Invalid or unsupported ADQL query string."}}
    },
    %{
      service: "NED",
      url: "https://ned.ipac.caltech.edu/tap",
      result:
        {"SELECT TOP 5 prefname, prefphytype, ra, dec, z, zflag FROM NEDTAP.objdir WHERE CONTAINS(POINT('J2000', ra, dec), CIRCLE('J2000', 56.75, 24.12, 0.2)) = 1",
         {:ok, ["prefname", "prefphytype", "ra", "dec", "z", "zflag"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "KOA",
      url: "https://koa.ipac.caltech.edu/TAP",
      result:
        {"SELECT TOP 5 koaid, instrume, targname, ra, dec, date_obs, progtitl FROM koa_hires",
         {:ok, ["koaid", "instrume", "targname", "ra", "dec", "date_obs", "progtitl"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, "Query is not a SELECT statemement."}}
    },
    %{
      service: "VizieR",
      url: "https://tapvizier.cds.unistra.fr/TAPVizieR/tap",
      result:
        {~s(SELECT TOP 5 HIP, RAICRS, DEICRS, Vmag, Plx, "B-V", SpType FROM "I/239/hip_main" WHERE HIP <= 5),
         {:ok, ["HIP", "RAICRS", "DEICRS", "Vmag", "Plx", "B-V", "SpType"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "SIMBAD",
      url: "https://simbad.cds.unistra.fr/simbad/sim-tap",
      result:
        {"SELECT TOP 5 main_id, ra, dec, otype, sp_type, plx_value FROM basic WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 0.1)) = 1",
         {:ok, ["main_id", "ra", "dec", "otype", "sp_type", "plx_value"]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "ESO",
      url: "https://archive.eso.org/tap_obs",
      result:
        {"SELECT TOP 5 obs_id, target_name, s_ra, s_dec, instrument_name, dataproduct_type, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1",
         {:ok,
          [
            "obs_id",
            "target_name",
            "s_ra",
            "s_dec",
            "instrument_name",
            "dataproduct_type",
            "em_min"
          ]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, ~s(Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "CADC",
      url: "https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus",
      result:
        {"SELECT TOP 5 obs_id, obs_collection, target_name, s_ra, s_dec, instrument_name, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1",
         {:ok,
          [
            "obs_id",
            "obs_collection",
            "target_name",
            "s_ra",
            "s_dec",
            "instrument_name",
            "em_min"
          ]}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s("ADQL syntax error: Encountered "" <S_IDENTIFIER> ""SELEC """")}}
    },
    %{
      service: "MAST",
      url: "https://mast.stsci.edu/vo-tap/api/v0.1/caom",
      result:
        {"SELECT TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :decode_error, 200, "expected text/csv, got text/xml"}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, ~s(Exception translating ADQL:  Encountered "SELEC".)}}
    }
  ]

  use ExUnit.Case, async: true, parameterize: @services

  alias SpaceTAP.{Error, Result}

  @moduletag :services
  @moduletag :capture_log
  @moduletag timeout: 180_000

  # IRSA and NED can take longer than Req's default of 15 seconds.
  @receive_timeout 120_000

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
    response = SpaceTAP.query(url, adql, req_options: [receive_timeout: @receive_timeout])

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
