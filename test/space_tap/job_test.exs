defmodule SpaceTAP.JobTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.{Error, Job}

  @service_url "https://tap.example.org/tap"
  @job_url "https://tap.example.org/tap/async/42"
  @adql "SELECT TOP 5 hipno FROM hipparcos.main"
  @req_options [plug: {Req.Test, SpaceTAP.Job}]
  @fixtures Path.expand("../fixtures", __DIR__)

  # Req logs each redirect, and a job comes after one.
  @moduletag :capture_log

  setup {Req.Test, :verify_on_exit!}

  describe "submit/3" do
    test "POSTs the query to the async endpoint with the parameters of a sync query" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "executing.xml"))

      assert {:ok, %Job{}} = submit()

      assert_received {:request, "POST", "/tap/async", params}

      # No PHASE=RUN: GAVO, ESO and CADC ignore it there.
      assert params == %{
               "REQUEST" => "doQuery",
               "LANG" => "ADQL",
               "FORMAT" => "csv",
               "QUERY" => @adql
             }
    end

    test "sends the format and MAXREC asked for, and keeps the format in the job" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "executing.xml"))

      assert {:ok, %Job{format: :votable}} = submit(format: :votable, maxrec: 0)
      assert_received {:request, "POST", "/tap/async", %{"FORMAT" => "votable", "MAXREC" => "0"}}
    end

    test "trims trailing slashes from the service URL, and sends SpaceTAP's User-Agent" do
      expect_request("POST", "/tap/async", fn conn ->
        assert Plug.Conn.get_req_header(conn, "user-agent") == [user_agent()]
        redirect(conn, 303, @job_url)
      end)

      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "executing.xml"))

      assert {:ok, %Job{}} = Job.submit(@service_url <> "//", @adql, req_options: @req_options)
    end

    test "starts a job the service leaves PENDING, as GAVO does" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "pending.xml"))
      expect_request("POST", "/tap/async/42/phase", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "completed.xml"))

      assert submit() ==
               {:ok,
                %Job{
                  url: @job_url,
                  phase: :completed,
                  format: :csv,
                  error_summary: nil,
                  result_url:
                    "http://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl/results/result"
                }}

      assert_received {:request, "POST", "/tap/async/42/phase", %{"PHASE" => "RUN"}}
    end

    test "leaves alone a job the service has started, as the Gaia archive does" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "executing.xml"))

      assert {:ok, %Job{url: @job_url, phase: :executing, result_url: nil}} = submit()
    end

    test "takes the URL of the job from where the redirects end" do
      # The NASA Exoplanet Archive answers with an http:// URL with a double
      # slash, which it redirects to https://.
      expect_request(
        "POST",
        "/tap/async",
        &redirect(&1, 303, "http://tap.example.org//tap/async/42")
      )

      expect_request(
        "GET",
        "//tap/async/42",
        &redirect(&1, 301, "https://tap.example.org//tap/async/42")
      )

      expect_request(
        "GET",
        "//tap/async/42",
        &job_document(&1, "exoplanet_archive", "completed.xml")
      )

      assert {:ok, %Job{url: "https://tap.example.org//tap/async/42", phase: :completed}} =
               submit()
    end

    test "returns the error document a service sends instead of a job" do
      expect_request(
        "POST",
        "/tap/async",
        &respond(&1, 400, "text/xml", fixture("gaia", "syntax_error.xml"))
      )

      assert {:error, %Error{type: :service_error, status: 400}} = submit()
    end

    test "is a :decode_error when the job document can't be read" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &respond(&1, 200, "text/html", "<html></html>"))

      assert submit() ==
               {:error,
                %Error{
                  type: :decode_error,
                  message: "expected a UWS job document, got text/html",
                  status: 200
                }}

      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &respond(&1, 200, "text/xml", "<job/>"))

      assert submit() ==
               {:error,
                %Error{type: :decode_error, message: "the job document has no phase", status: 200}}
    end

    test "is a :transport_error when the service can't be reached" do
      expect_request("POST", "/tap/async", &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %Error{type: :transport_error, status: nil}} = submit()
    end

    test "raises on an option it doesn't know or can't use" do
      assert_raise ArgumentError, ~r/unknown keys \[:timeout\]/, fn -> submit(timeout: 1000) end

      assert_raise ArgumentError, ~r/:format to be :csv or :votable/, fn ->
        submit(format: :fits)
      end

      assert_raise ArgumentError, ~r/:maxrec to be a non-negative integer/, fn ->
        submit(maxrec: -1)
      end

      assert_raise ArgumentError, ~r/:req_options to be a keyword list/, fn ->
        Job.submit(@service_url, @adql, req_options: :nope)
      end
    end
  end

  describe "get/2" do
    test "reads the job at its URL" do
      expect_request("GET", "/tap/async/42", &job_document(&1, "cadc", "completed.xml"))

      assert get() ==
               {:ok,
                %Job{
                  url: @job_url,
                  phase: :completed,
                  format: :csv,
                  error_summary: nil,
                  result_url:
                    "https://ws-cadc.canfar.net/minoc/files/tmp:argus/result_y374m4kk4ey22u8g.xml"
                }}
    end

    test "keeps the format it is given, which the job document can't be trusted for" do
      expect_request("GET", "/tap/async/42", &job_document(&1, "cadc", "completed.xml"))

      assert {:ok, %Job{format: :votable}} = get(format: :votable)
    end

    test "reads the error summary of a job that failed" do
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "error.xml"))

      assert {:ok,
              %Job{phase: :error, error_summary: "Field query: No such field known" <> _rest}} =
               get()
    end

    test "resolves a relative result URL against the URL of the job (RFC 3986 §5.2)" do
      document = """
      <job><phase>COMPLETED</phase><results>
        <result id="result" href="42/results/result"/>
      </results></job>
      """

      expect_request("GET", "/tap/async/42", &respond(&1, 200, "text/xml", document))

      assert {:ok, %Job{result_url: "https://tap.example.org/tap/async/42/results/result"}} =
               get()
    end

    test "returns the error for a job the service doesn't have" do
      # NED, ESO and MAST answer 404 with an error document, the Gaia archive
      # with HTML.
      expect_request(
        "GET",
        "/tap/async/42",
        &respond(&1, 404, "text/xml", fixture("gaia", "syntax_error.xml"))
      )

      assert {:error, %Error{type: :service_error, status: 404}} = get()

      expect_request("GET", "/tap/async/42", &respond(&1, 404, "text/html", "<html></html>"))
      assert {:error, %Error{type: :http_error, status: 404}} = get()
    end

    test "raises on an option it doesn't know or can't use" do
      assert_raise ArgumentError, ~r/unknown keys \[:maxrec\]/, fn -> get(maxrec: 5) end
      assert_raise ArgumentError, ~r/:format to be :csv or :votable/, fn -> get(format: :fits) end
    end
  end

  describe "delete/2" do
    test "sends DELETE, without following the 303 to the list of jobs" do
      expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))

      assert delete() == :ok
    end

    test "POSTs ACTION=DELETE when the service refuses DELETE, as NED, KOA and the NASA Exoplanet Archive do" do
      for {status, answer} <- [{403, 303}, {500, 200}, {502, 200}] do
        expect_request("DELETE", "/tap/async/42", &respond(&1, status, "text/html", ""))

        expect_request("POST", "/tap/async/42", fn conn ->
          if answer == 303,
            do: redirect(conn, 303, @service_url <> "/async"),
            else: respond(conn, 200, "text/xml", fixture("koa", "completed.xml", "jobs"))
        end)

        assert delete() == :ok
        assert_received {:request, "POST", "/tap/async/42", %{"ACTION" => "DELETE"}}
      end
    end

    test "returns the error when neither way deletes the job, as for one already destroyed" do
      expect_request("DELETE", "/tap/async/42", &respond(&1, 404, "text/html", ""))
      expect_request("POST", "/tap/async/42", &respond(&1, 404, "text/html", ""))

      assert {:error, %Error{type: :http_error, status: 404}} = delete()
    end

    test "returns a :transport_error without trying again" do
      expect_request("DELETE", "/tap/async/42", &Req.Test.transport_error(&1, :timeout))

      assert {:error, %Error{type: :transport_error}} = delete()
    end

    test "raises on an option it doesn't know" do
      assert_raise ArgumentError, ~r/unknown keys \[:format\]/, fn -> delete(format: :csv) end
    end
  end

  defp submit(opts \\ []) do
    Job.submit(@service_url, @adql, Keyword.put_new(opts, :req_options, @req_options))
  end

  defp get(opts \\ []) do
    Job.get(@job_url, Keyword.put_new(opts, :req_options, @req_options))
  end

  defp delete(opts \\ []) do
    job = %Job{url: @job_url, phase: :completed, format: :csv}
    Job.delete(job, Keyword.put_new(opts, :req_options, @req_options))
  end

  # Stands in for the next request the TAP service gets: checks its method
  # and path, sends it to the test process with the form parameters decoded,
  # and answers with respond.
  defp expect_request(method, path, respond) do
    test = self()

    Req.Test.expect(SpaceTAP.Job, fn conn ->
      assert {conn.method, conn.request_path} == {method, path}
      {:ok, form, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, method, path, URI.decode_query(form)})
      respond.(conn)
    end)
  end

  defp respond(conn, status, content_type, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", content_type)
    |> Plug.Conn.send_resp(status, body)
  end

  defp redirect(conn, status, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end

  defp job_document(conn, service, name),
    do: respond(conn, 200, "text/xml", fixture(service, name, "jobs"))

  defp fixture(service, name, folder \\ "."),
    do: File.read!(Path.join([@fixtures, service, folder, name]))

  defp user_agent, do: "space_tap/" <> to_string(Application.spec(:space_tap, :vsn))
end
