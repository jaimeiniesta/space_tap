defmodule SpaceTAP.Test.Services do
  @moduledoc false

  # The services in the README's Compatibility table, with the queries of
  # their fixtures as {adql, expected} pairs. A result expects these columns
  # and this many rows, with VOTable and with CSV, unless
  # `csv_result` says what CSV gives instead, or `async_csv_result` what it
  # gives for an async job; an error expects its type,
  # status and a part of its message that the service is unlikely to reword.
  # The services tests and the parity tests both read them, so a service that
  # changes how it answers is updated here and in its fixtures.
  #
  # Where TOP keeps fewer rows than the WHERE of a fixture's query matches,
  # the query here adds an ORDER BY on a unique column. Without one, the order
  # of the rows, and so which ones TOP keeps, is up to the service (ADQL 2.1
  # §2.2), and the parity tests would compare different rows: CADC sent other
  # rows on each query on 2026-11-16. ORDER BY comes before TOP (ADQL 2.1
  # §4.10.1), but where a service applies TOP first the query names its rows
  # instead.

  @typedoc "What a query should give: a result's columns and row count, or an error."
  @type expected ::
          {:ok, [String.t()], non_neg_integer()}
          | {:error, SpaceTAP.Error.type(), pos_integer(), String.t()}

  @typedoc "A service, its URL and the queries of its fixtures."
  @type t :: %{
          required(:service) => String.t(),
          required(:url) => String.t(),
          required(:result) => {String.t(), expected()},
          optional(:csv_result) => expected(),
          optional(:async_csv_result) => expected(),
          optional(:metadata) => {String.t(), String.t(), String.t()},
          required(:syntax_error) => {String.t(), expected()}
        }

  @services [
    %{
      service: "Gaia",
      url: "https://gea.esac.esa.int/tap-server/tap",
      result:
        {"SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag",
         {:ok, ["source_id", "designation", "ra", "dec", "parallax", "phot_g_mean_mag"], 5}},
      syntax_error:
        {"SELEC TOP 3 source_id FROM gaiadr3.gaia_source",
         {:error, :service_error, 400, "Cannot parse query 'SELEC TOP 3 source_id"}}
    },
    %{
      service: "GAVO",
      url: "https://dc.g-vo.org/tap",
      result:
        {"SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 5",
         {:ok, ["hipno", "ra", "dec", "vmag", "parallax", "SpType"], 5}},
      metadata: {"hipparcos", "hipparcos.main", "hipno"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM tap_schema.tables",
         {:error, :service_error, 500, "Field query: Could not parse your query: Expected SELECT"}}
    },
    %{
      service: "NASA Exoplanet Archive",
      url: "https://exoplanetarchive.ipac.caltech.edu/TAP",
      # The archive applies TOP before ORDER BY, so TOP 3, the query of
      # planets.csv, may give other planets each time, and the parity tests
      # would compare different rows. This query names its planets instead,
      # and default_flag = 1 picks one row of parameters for each.
      result:
        {"SELECT pl_name, disc_year FROM ps WHERE default_flag = 1 AND pl_name IN ('WASP-39 b', 'GJ 436 b', 'HAT-P-1 b')",
         {:ok, ["pl_name", "disc_year"], 3}},
      metadata: {"exo_tap", "ps", "pl_name"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, "Query is not a SELECT statemement."}}
    },
    %{
      service: "IRSA",
      url: "https://irsa.ipac.caltech.edu/TAP",
      # No ORDER BY yet: IRSA answered with HTTP 502 on 2026-11-16, so it
      # couldn't be checked that it sorts before TOP.
      result:
        {"SELECT TOP 5 table_name, column_name, datatype, unit, description FROM TAP_SCHEMA.columns WHERE table_name = 'fp_psc'",
         {:ok, ["table_name", "column_name", "datatype", "unit", "description"], 5}},
      metadata: {"2mass", "fp_psc", "ra"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 200,
          "UsageFault: BAD_REQUEST: Invalid or unsupported ADQL query string."}},
      # The result of an async job asked for as CSV is CSV labelled
      # application/x-votable+xml, which isn't read (ADR 0006), where the sync
      # query labels it text/csv. Checked on 2026-11-17.
      async_csv_result:
        {:error, :decode_error, 200, "expected text/csv, got application/x-votable+xml"}
    },
    %{
      service: "NED",
      url: "https://ned.ipac.caltech.edu/tap",
      result:
        {"SELECT TOP 5 prefname, prefphytype, ra, dec, z, zflag FROM NEDTAP.objdir WHERE CONTAINS(POINT('J2000', ra, dec), CIRCLE('J2000', 56.75, 24.12, 0.2)) = 1 ORDER BY prefname",
         {:ok, ["prefname", "prefphytype", "ra", "dec", "z", "zflag"], 5}},
      metadata: {"NEDTAP", "NEDTAP.objdir", "prefname"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "KOA",
      url: "https://koa.ipac.caltech.edu/TAP",
      # KOA applies TOP before ORDER BY, like the NASA Exoplanet Archive: with
      # ORDER BY koaid, ASC and DESC gave the same five files. This query
      # names the five files of hires.csv instead.
      result:
        {"SELECT koaid, instrume, targname, ra, dec, date_obs, progtitl FROM koa_hires WHERE koaid IN ('HI.19941118.65412.fits', 'HI.19941201.80171.fits', 'HI.19941201.80420.fits', 'HI.19941201.83588.fits', 'HI.19941210.06503.fits')",
         {:ok, ["koaid", "instrume", "targname", "ra", "dec", "date_obs", "progtitl"], 5}},
      metadata: {"koa_tap", "koa_hires", "koaid"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, "Query is not a SELECT statemement."}}
    },
    %{
      service: "VizieR",
      url: "https://tapvizier.cds.unistra.fr/TAPVizieR/tap",
      result:
        {~s(SELECT TOP 5 HIP, RAICRS, DEICRS, Vmag, Plx, "B-V", SpType FROM "I/239/hip_main" WHERE HIP <= 5),
         {:ok, ["HIP", "RAICRS", "DEICRS", "Vmag", "Plx", "B-V", "SpType"], 5}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "SIMBAD",
      url: "https://simbad.cds.unistra.fr/simbad/sim-tap",
      # No ORDER BY yet: CDS didn't answer on 2026-11-16, so it couldn't be
      # checked that SIMBAD sorts before TOP.
      result:
        {"SELECT TOP 5 main_id, ra, dec, otype, sp_type, plx_value FROM basic WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 0.1)) = 1",
         {:ok, ["main_id", "ra", "dec", "otype", "sp_type", "plx_value"], 5}},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "ESO",
      url: "https://archive.eso.org/tap_obs",
      result:
        {"SELECT TOP 5 obs_id, target_name, s_ra, s_dec, instrument_name, dataproduct_type, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1 ORDER BY obs_publisher_did",
         {:ok,
          [
            "obs_id",
            "target_name",
            "s_ra",
            "s_dec",
            "instrument_name",
            "dataproduct_type",
            "em_min"
          ], 5}},
      metadata: {"ivoa", "ivoa.ObsCore", "obs_id"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, ~s(Encountered "SELEC". Was expecting: "SELECT")}}
    },
    %{
      service: "CADC",
      url: "https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus",
      result:
        {"SELECT TOP 5 obs_id, obs_collection, target_name, s_ra, s_dec, instrument_name, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1 ORDER BY obs_publisher_did",
         {:ok,
          [
            "obs_id",
            "obs_collection",
            "target_name",
            "s_ra",
            "s_dec",
            "instrument_name",
            "em_min"
          ], 5}},
      metadata: {"ivoa", "ivoa.ObsCore", "obs_id"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400,
          ~s("ADQL syntax error: Encountered "" <S_IDENTIFIER> ""SELEC """")}}
    },
    %{
      service: "MAST",
      url: "https://mast.stsci.edu/vo-tap/api/v0.1/caom",
      result:
        {"SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name",
         {:ok, ["table_name"], 3}},
      # MAST sends VOTable when CSV is requested (ADR 0006), but CSV as the
      # result of an async job. Checked on 2026-11-17.
      csv_result:
        {:error, :decode_error, 200,
         "expected text/csv, got text/xml: the response is a VOTable, pass format: :votable to read it"},
      async_csv_result: {:ok, ["table_name"], 3},
      metadata: {"ivoa", "ivoa.obscore", "obs_id"},
      syntax_error:
        {"SELEC TOP 3 table_name FROM TAP_SCHEMA.tables",
         {:error, :service_error, 400, ~s(Exception translating ADQL:  Encountered "SELEC".)}}
    }
  ]

  @spec all() :: [t()]
  def all, do: @services

  # The services whose TAP_SCHEMA was checked, with `metadata` naming the
  # schema and the table of their TAP_SCHEMA fixtures and a column of that
  # table. VizieR and SIMBAD get theirs when CDS answers again: it was down
  # when the others were captured, on 2026-11-18. Gaia has none because
  # tables/2 fails there, as its fixtures README explains: its
  # TAP_SCHEMA.tables has descriptions that aren't ASCII, and any WHERE on
  # that table gives HTTP 500.
  @spec with_metadata() :: [t()]
  def with_metadata, do: Enum.filter(@services, &Map.has_key?(&1, :metadata))

  # What the query of `result` gives when CSV is requested.
  @spec csv_result(t()) :: expected()
  def csv_result(%{result: {_adql, expected}} = service),
    do: Map.get(service, :csv_result, expected)

  # What it gives when CSV is requested for an async job, the same as for a
  # sync query unless `async_csv_result` says otherwise.
  @spec async_csv_result(t()) :: expected()
  def async_csv_result(service), do: Map.get(service, :async_csv_result, csv_result(service))

  # IRSA and NED can take longer than Req's default of 15 seconds.
  @spec req_options() :: keyword()
  def req_options, do: [receive_timeout: 120_000]
end
