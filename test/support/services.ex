defmodule SpaceTAP.Test.Services do
  @moduledoc false

  # The services in the README's Compatibility table other than Gaia and the
  # NASA Exoplanet Archive, which the integration tests cover, with the
  # queries of their fixtures as {adql, expected} pairs. A result expects
  # these columns and 5 rows; an error expects its type, status and a part of
  # its message that the service is unlikely to reword. The services tests
  # and the parity tests both read them, so a service that changes how it
  # answers is updated here and in its fixtures.

  @typedoc "What a query should give: a result's columns, or an error."
  @type expected ::
          {:ok, [String.t()]} | {:error, SpaceTAP.Error.type(), pos_integer(), String.t()}

  @typedoc "A service, its URL and the queries of its fixtures."
  @type t :: %{
          service: String.t(),
          url: String.t(),
          result: {String.t(), expected()},
          syntax_error: {String.t(), expected()}
        }

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

  @spec all() :: [t()]
  def all, do: @services

  # MAST answers with VOTable, which SpaceTAP doesn't read yet, so there is
  # no result to compare with pyvo's.
  @spec with_result() :: [t()]
  def with_result, do: Enum.filter(@services, &match?(%{result: {_adql, {:ok, _columns}}}, &1))

  # IRSA and NED can take longer than Req's default of 15 seconds.
  @spec req_options() :: keyword()
  def req_options, do: [receive_timeout: 120_000]
end
