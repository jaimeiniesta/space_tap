defmodule SpaceTAPServicesTest do
  # Responses captured from the services in the README's Compatibility table,
  # served with the status and Content-Type each service sent. Each service
  # folder in test/fixtures says how they were captured. The integration tests
  # check that the services still answer this way.
  use ExUnit.Case, async: true

  alias SpaceTAP.{Error, Result}

  @fixtures Path.expand("fixtures", __DIR__)

  # {service, fixture, status, Content-Type, columns, {row index, row}}. Each
  # result has 5 rows.
  @csv_results [
    {"GAVO", "gavo/hipparcos.csv", 200, "text/csv;header=present",
     ["hipno", "ra", "dec", "vmag", "parallax", "SpType"],
     {0, ["1", "0.00091185", "1.08901332", "9.1", "9.833333e-07", "F5"]}},
    {"IRSA", "irsa/columns.csv", 200, "text/csv",
     ["table_name", "column_name", "datatype", "unit", "description"],
     {0, ["fp_psc", "ra", "double", "deg", "right ascension (J2000 decimal deg)"]}},
    {"NED", "ned/objdir.csv", 200, "text/csv;charset=UTF-8",
     ["prefname", "prefphytype", "ra", "dec", "z", "zflag"],
     {0, ["2XMM J034620.0+241343", nil, "56.58365208333", "24.22884694444", nil, nil]}},
    {"KOA", "koa/hires.csv", 200, "text/plain; charset=UTF-8",
     ["koaid", "instrume", "targname", "ra", "dec", "date_obs", "progtitl"],
     {0,
      [
        "HI.19941118.65412.fits",
        "HIRES Spectrograph",
        nil,
        "15.84556",
        "70.26828",
        "1994-11-18 00:00:00",
        "Program Title Not Found"
      ]}},
    {"VizieR", "vizier/hip_main.csv", 200, "text/csv;charset=UTF-8",
     ["HIP", "RAICRS", "DEICRS", "Vmag", "Plx", "B-V", "SpType"],
     {0, ["1", "9.1185E-4", "1.08901332", "9.1", "3.54", "0.482", "F5"]}},
    {"SIMBAD", "simbad/basic.csv", 200, "text/csv;charset=UTF-8",
     ["main_id", "ra", "dec", "otype", "sp_type", "plx_value"],
     {3, ["Cl* Melotte   22     VM      13", "56.675", "24.1", "*", nil, nil]}},
    {"ESO", "eso/obscore.csv", 200, "text/csv",
     ["obs_id", "target_name", "s_ra", "s_dec", "instrument_name", "dataproduct_type", "em_min"],
     {0,
      ["962640", "28Tau", "57.296784", "24.13606", "XSHOOTER", "spectrum", "5.336599999999999E-7"]}}
  ]

  # {service, fixture, status, Content-Type, message}
  @service_errors [
    {"the NASA Exoplanet Archive", "exoplanet_archive/syntax_error.xml", 400, "application/xml",
     "Query is not a SELECT statemement."},
    {"IRSA", "irsa/syntax_error.xml", 200, "text/xml",
     "UsageFault: BAD_REQUEST: Invalid or unsupported ADQL query string. See TAP documentation here: https://irsa.ipac.caltech.edu/docs/program_interface/TAP.html"},
    {"NED", "ned/syntax_error.xml", 400, "application/xml;charset=UTF-8",
     ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")},
    {"VizieR", "vizier/syntax_error.xml", 400, "application/xml;charset=UTF-8",
     ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")},
    {"SIMBAD", "simbad/syntax_error.xml", 400, "application/xml;charset=UTF-8",
     ~s(Incorrect ADQL query:  Encountered "SELEC". Was expecting: "SELECT")},
    {"ESO", "eso/syntax_error.xml", 400, "application/xml",
     ~s(Encountered "SELEC". Was expecting: "SELECT")},
    {"KOA", "koa/syntax_error.txt", 400, "text/plain; charset=UTF-8",
     "Query is not a SELECT statemement."}
  ]

  describe "CSV results" do
    for {service, fixture, status, content_type, columns, {index, row}} <- @csv_results do
      test "reads #{service}'s CSV" do
        assert {:ok, %Result{columns: columns, rows: rows}} =
                 respond(unquote(fixture), unquote(status), unquote(content_type))

        assert columns == unquote(columns)
        assert length(rows) == 5
        assert Enum.at(rows, unquote(index)) == unquote(row)
      end
    end

    # CADC answers the POST with a 303 to the job's result (TAP 1.1 §2.1).
    @tag :capture_log
    test "reads CADC's CSV after its redirect" do
      Req.Test.stub(SpaceTAP, fn
        %Plug.Conn{method: "POST"} = conn ->
          redirect(conn, 303, "https://tap.example.org/tap/sync/job/run")

        %Plug.Conn{method: "GET"} = conn ->
          send_fixture(conn, "cadc/obscore.csv", 200, "text/csv; header=present")
      end)

      assert {:ok, %Result{columns: columns, rows: rows}} = query()

      assert columns ==
               [
                 "obs_id",
                 "obs_collection",
                 "target_name",
                 "s_ra",
                 "s_dec",
                 "instrument_name",
                 "em_min"
               ]

      assert length(rows) == 5

      assert hd(rows) == [
               "SCLA_056.746+24.113",
               "SUBARUCADC",
               "M45 5",
               "56.7461695677341",
               "24.113327777113355",
               "Suprime-Cam",
               "6.801500000000001E-7"
             ]
    end
  end

  describe "error documents" do
    for {service, fixture, status, content_type, message} <- @service_errors do
      test "returns #{service}'s error document as a service error" do
        assert respond(unquote(fixture), unquote(status), unquote(content_type)) ==
                 {:error,
                  %Error{type: :service_error, status: unquote(status), message: unquote(message)}}
      end
    end

    # CADC sends its error as plain text with HTTP 400 after its redirect. The
    # message is a CSV field, quotes included, because CSV was requested.
    @tag :capture_log
    test "returns CADC's plain-text error, sent after its redirect, as a service error" do
      Req.Test.stub(SpaceTAP, fn
        %Plug.Conn{method: "POST"} = conn ->
          redirect(conn, 303, "https://tap.example.org/tap/sync/job/run")

        %Plug.Conn{method: "GET"} = conn ->
          send_fixture(conn, "cadc/syntax_error.txt", 400, "text/plain")
      end)

      assert {:error, %Error{type: :service_error, status: 400, message: message}} = query()
      assert message =~ ~r/\A"ADQL syntax error: Encountered "" <S_IDENTIFIER> ""SELEC """"/
    end
  end

  describe "responses that aren't CSV" do
    test "returns a decode error for MAST, which sends VOTable when CSV is requested" do
      assert respond("mast/tables.xml", 200, "text/xml; charset=utf-8") ==
               {:error,
                %Error{
                  type: :decode_error,
                  status: 200,
                  message: "expected text/csv, got text/xml"
                }}
    end

    # Gaia redirects http:// to https:// with a 302, which Req follows with a
    # GET that carries no query (RFC 9110 §15.4.3). Gaia answers it with its
    # list of async jobs.
    @tag :capture_log
    test "returns a decode error for Gaia's job list, its answer after an http:// redirect" do
      Req.Test.stub(SpaceTAP, fn
        %Plug.Conn{method: "POST"} = conn ->
          redirect(conn, 302, "https://tap.example.org/tap/sync")

        %Plug.Conn{method: "GET"} = conn ->
          send_fixture(conn, "gaia/sync_get.xml", 200, "text/xml;charset=UTF-8")
      end)

      assert query() ==
               {:error,
                %Error{
                  type: :decode_error,
                  status: 200,
                  message: "expected text/csv, got text/xml"
                }}
    end
  end

  #####################
  # Private functions #
  #####################

  defp query do
    SpaceTAP.query("https://tap.example.org/tap", "SELECT 1",
      req_options: [plug: {Req.Test, SpaceTAP}]
    )
  end

  defp respond(fixture, status, content_type) do
    Req.Test.stub(SpaceTAP, &send_fixture(&1, fixture, status, content_type))
    query()
  end

  defp send_fixture(conn, fixture, status, content_type) do
    conn
    |> Plug.Conn.put_resp_header("content-type", content_type)
    |> Plug.Conn.send_resp(status, File.read!(Path.join(@fixtures, fixture)))
  end

  defp redirect(conn, status, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end
end
