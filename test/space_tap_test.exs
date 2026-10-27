defmodule SpaceTAPTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.{Error, Result}

  @service_url "https://tap.example.org/tap"
  @adql "SELECT TOP 5 source_id FROM gaiadr3.gaia_source"
  @req_options [plug: {Req.Test, SpaceTAP}]
  @fixtures Path.expand("fixtures/gaia", __DIR__)

  describe "query/3 request" do
    test "POSTs the ADQL query as CSV to the sync endpoint of the service URL" do
      stub_csv()

      assert {:ok, %Result{}} = query()
      assert_received {:request, conn, params}

      assert conn.method == "POST"
      assert conn.host == "tap.example.org"
      assert conn.request_path == "/tap/sync"

      assert params == %{
               "REQUEST" => "doQuery",
               "LANG" => "ADQL",
               "FORMAT" => "csv",
               "QUERY" => @adql
             }
    end

    test "trims trailing slashes from the service URL" do
      stub_csv()

      for service_url <- [@service_url <> "/", @service_url <> "//"] do
        assert {:ok, %Result{}} = query_at(service_url)
        assert_received {:request, %Plug.Conn{request_path: "/tap/sync"}, _params}
      end
    end

    test "treats a service URL ending in /sync as a base URL too" do
      stub_csv()

      assert {:ok, %Result{}} = query_at(@service_url <> "/sync")
      assert_received {:request, %Plug.Conn{request_path: "/tap/sync/sync"}, _params}
    end

    test "sends :maxrec as MAXREC" do
      stub_csv()

      assert {:ok, %Result{}} = query(maxrec: 3)
      assert_received {:request, _conn, %{"MAXREC" => "3"}}
    end

    test "sends MAXREC=0, which asks for the columns with no rows" do
      stub_service(200, "text/csv", fixture("maxrec_0.csv"))

      assert {:ok, %Result{columns: ["source_id", "ra", "dec"], rows: []}} = query(maxrec: 0)
      assert_received {:request, _conn, %{"MAXREC" => "0"}}
    end

    test "identifies itself as space_tap/<version>" do
      stub_csv()

      assert {:ok, %Result{}} = query()
      assert_received {:request, conn, _params}

      assert Plug.Conn.get_req_header(conn, "user-agent") == [user_agent()]
    end

    test ":req_options can't change the TAP request" do
      stub_csv()

      req_options =
        @req_options ++
          [
            url: "https://other.example.org/",
            form: [QUERY: "SELECT 1"],
            decode_body: true,
            user_agent: "other"
          ]

      assert {:ok, %Result{}} = query(req_options: req_options)
      assert_received {:request, conn, %{"QUERY" => @adql}}

      assert conn.host == "tap.example.org"
      assert Plug.Conn.get_req_header(conn, "user-agent") == [user_agent()]
    end

    test "passes other :req_options to Req, such as headers" do
      stub_csv()

      assert {:ok, %Result{}} =
               query(req_options: @req_options ++ [headers: [x_request_id: "42"]])

      assert_received {:request, conn, _params}

      assert Plug.Conn.get_req_header(conn, "x-request-id") == ["42"]
    end

    # Req logs each redirect.
    @tag :capture_log
    test "follows a redirect from the sync endpoint with GET" do
      test = self()

      Req.Test.stub(SpaceTAP, fn
        %Plug.Conn{method: "POST", request_path: "/tap/sync"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "https://tap.example.org/tap/results/1")
          |> Plug.Conn.send_resp(303, "")

        conn ->
          send(test, {:redirected, conn.method, conn.request_path})

          conn
          |> put_content_type("text/csv")
          |> Plug.Conn.send_resp(200, fixture("pleiades.csv"))
      end)

      assert {:ok, %Result{rows: rows}} = query()
      assert length(rows) == 5
      assert_received {:redirected, "GET", "/tap/results/1"}
    end
  end

  describe "query/3 options" do
    test "raise on an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:max_rec\]/, fn ->
        SpaceTAP.query(@service_url, @adql, max_rec: 3)
      end
    end

    test "raise when :maxrec is not a non-negative integer" do
      for maxrec <- [-1, 1.5, "3"] do
        assert_raise ArgumentError, ~r/expected :maxrec to be a non-negative integer/, fn ->
          SpaceTAP.query(@service_url, @adql, maxrec: maxrec)
        end
      end
    end

    test "raise when :req_options is not a keyword list" do
      assert_raise ArgumentError, ~r/expected :req_options to be a keyword list/, fn ->
        SpaceTAP.query(@service_url, @adql, req_options: %{})
      end
    end
  end

  describe "query/3 response" do
    test "returns the result of a CSV response" do
      stub_csv()

      assert {:ok, %Result{columns: columns, rows: rows}} = query()
      assert columns == ["source_id", "designation", "ra", "dec", "parallax", "phot_g_mean_mag"]
      assert length(rows) == 5
    end

    test "reads the media type case-insensitively, ignoring its parameters" do
      stub_service(200, "Text/CSV; header=present", fixture("pleiades.csv"))

      assert {:ok, %Result{rows: rows}} = query()
      assert length(rows) == 5
    end

    test "returns a service error from Gaia's VOTable error document" do
      stub_service(400, "application/xml;charset=UTF-8", fixture("syntax_error.xml"))

      assert {:error, %Error{type: :service_error, status: 400, message: message}} = query()
      assert message =~ ~r/\ACannot parse query 'SELEC TOP 3 source_id/
    end

    test "returns a service error from an error document sent with HTTP 200" do
      stub_service(200, "application/xml;charset=UTF-8", fixture("unknown_table.xml"))

      assert {:error, %Error{type: :service_error, status: 200, message: message}} = query()
      assert message =~ ~s(Unknown table "gaiadr3.no_such_table")
    end

    test "returns a service error with a message of its own when the error document has none" do
      xml = ~s(<VOTABLE><RESOURCE><INFO name="QUERY_STATUS" value="ERROR"/></RESOURCE></VOTABLE>)
      stub_service(400, "application/x-votable+xml", xml)

      assert query() ==
               {:error,
                %Error{
                  type: :service_error,
                  status: 400,
                  message: "the TAP service reported an error without a message"
                }}
    end

    test "returns the error instead of raising when :req_options asks Req to raise" do
      stub_service(400, "application/xml;charset=UTF-8", fixture("syntax_error.xml"))

      assert {:error, %Error{type: :service_error, status: 400}} =
               query(req_options: @req_options ++ [http_errors: :raise])
    end

    test "reads the whole body when :req_options asks Req to stream it" do
      stub_csv()

      assert {:ok, %Result{rows: rows}} = query(req_options: @req_options ++ [into: []])
      assert length(rows) == 5
    end

    test "returns an HTTP error with the text of a plain-text body, such as a proxy's" do
      message = "upstream connect error or disconnect/reset before headers"
      stub_service(503, "text/plain", message <> "\n")

      assert query() == {:error, %Error{type: :http_error, status: 503, message: message}}
    end

    test "returns an HTTP error for plain text with a 4xx status too, which carries no query status" do
      stub_service(400, "text/plain;charset=UTF-8", "\nLANG=SQL is not supported\n")

      assert query() ==
               {:error,
                %Error{type: :http_error, status: 400, message: "LANG=SQL is not supported"}}
    end

    test "returns an HTTP error for an empty plain-text body" do
      stub_service(404, "text/plain", "")

      assert query() ==
               {:error,
                %Error{type: :http_error, status: 404, message: "unexpected text/plain response"}}
    end

    test "returns a decode error for malformed CSV" do
      stub_service(200, "text/csv", "source_id,ra\n1\n")

      assert query() ==
               {:error,
                %Error{
                  type: :decode_error,
                  status: 200,
                  message: "data row 1 has 1 fields, expected 2"
                }}
    end

    test "returns a decode error for a successful response in another format" do
      stub_service(200, "application/x-votable+xml", fixture("ok.xml"))

      assert query() ==
               {:error,
                %Error{
                  type: :decode_error,
                  status: 200,
                  message: "expected text/csv, got application/x-votable+xml"
                }}
    end

    test "returns a decode error for a successful response with no or an empty Content-Type" do
      for content_type <- [nil, ""] do
        stub_service(200, content_type, fixture("pleiades.csv"))

        assert query() ==
                 {:error,
                  %Error{
                    type: :decode_error,
                    status: 200,
                    message: "expected text/csv, got no Content-Type"
                  }}
      end
    end

    test "returns an HTTP error for an error status without an error document" do
      stub_service(502, "text/html", "<html><body>Bad Gateway</body></html>")

      assert query() ==
               {:error,
                %Error{type: :http_error, status: 502, message: "unexpected text/html response"}}
    end

    test "returns an HTTP error for an XML document that isn't an error document" do
      stub_service(500, "text/xml", "<error>Internal Server Error</error>")

      assert query() ==
               {:error,
                %Error{type: :http_error, status: 500, message: "unexpected text/xml response"}}
    end

    test "returns an HTTP error for an error status with no or an empty Content-Type" do
      for content_type <- [nil, ""] do
        stub_service(503, content_type, "")

        assert query() ==
                 {:error,
                  %Error{
                    type: :http_error,
                    status: 503,
                    message: "unexpected response with no Content-Type"
                  }}
      end
    end

    test "returns a transport error when no response arrives" do
      Req.Test.stub(SpaceTAP, &Req.Test.transport_error(&1, :econnrefused))

      assert query() ==
               {:error,
                %Error{type: :transport_error, status: nil, message: "connection refused"}}
    end

    @tag :capture_log
    test "returns a transport error when the redirects never end" do
      Req.Test.stub(SpaceTAP, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://tap.example.org/tap/sync")
        |> Plug.Conn.send_resp(303, "")
      end)

      assert {:error, %Error{type: :transport_error, status: nil, message: message}} = query()
      assert message =~ "too many redirects"
    end
  end

  #####################
  # Private functions #
  #####################

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp query(opts \\ []), do: query_at(@service_url, opts)

  defp query_at(service_url, opts \\ []) do
    SpaceTAP.query(service_url, @adql, Keyword.put_new(opts, :req_options, @req_options))
  end

  # Stands in for the TAP service: sends the request it gets to the test
  # process, with the form parameters decoded, and answers with the given
  # status, Content-Type (none when nil) and body.
  defp stub_service(status, content_type, body) do
    test = self()

    Req.Test.stub(SpaceTAP, fn conn ->
      {:ok, form, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn, URI.decode_query(form)})

      conn
      |> put_content_type(content_type)
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp put_content_type(conn, nil), do: conn

  defp put_content_type(conn, content_type) do
    Plug.Conn.put_resp_header(conn, "content-type", content_type)
  end

  defp stub_csv, do: stub_service(200, "text/csv", fixture("pleiades.csv"))

  defp user_agent, do: "space_tap/" <> to_string(Application.spec(:space_tap, :vsn))
end
