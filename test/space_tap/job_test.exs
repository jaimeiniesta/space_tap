defmodule SpaceTAP.JobTest do
  use ExUnit.Case, async: true

  import SpaceTAP.Test.AsyncService

  alias SpaceTAP.{Error, Job, Result}

  @service_url "https://tap.example.org/tap"
  @job_url "https://tap.example.org/tap/async/42"
  @adql "SELECT TOP 5 hipno FROM hipparcos.main"
  @req_options req_options()

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

    test "reads the job at its URL once started, wherever the service redirects" do
      # The Gaia archive redirects to <job>/phase, which is text/plain.
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "pending.xml"))
      expect_request("POST", "/tap/async/42/phase", &redirect(&1, 303, @job_url <> "/phase"))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "executing.xml"))

      assert {:ok, %Job{url: @job_url, phase: :executing}} = submit()
    end

    test "returns the error a service gives when it won't start the job, and deletes the job" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "pending.xml"))

      expect_request(
        "POST",
        "/tap/async/42/phase",
        &respond(&1, 403, "text/xml", fixture("gaia", "syntax_error.xml"))
      )

      # The error doesn't give the job's URL, so nothing else could delete it.
      expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))

      assert {:error, %Error{type: :service_error, status: 403}} = submit()
    end

    test "leaves alone a job that is no longer PENDING" do
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

    test "is a :decode_error when the job document can't be read, and deletes the job" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &respond(&1, 200, "text/html", "<html></html>"))
      expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))

      assert submit() ==
               {:error,
                %Error{
                  type: :decode_error,
                  message: "expected a UWS job document, got text/html",
                  status: 200
                }}

      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &respond(&1, 200, "text/xml", "<job/>"))
      expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))

      assert submit() ==
               {:error,
                %Error{type: :decode_error, message: "the job document has no phase", status: 200}}
    end

    test "takes only a 303 for the new job, not a redirect from http:// to https://" do
      # Its Location is the list of jobs, where a POST to delete would create one.
      for status <- [301, 302, 307, 308] do
        expect_request("POST", "/tap/async", &redirect(&1, status, @service_url <> "/async"))

        assert submit() ==
                 {:error,
                  %Error{
                    type: :http_error,
                    message:
                      "expected a 303 to the new job (UWS 1.1 §2.2.3.1), got a redirect to " <>
                        "https://tap.example.org/tap/async",
                    status: status
                  }}
      end
    end

    test "creates nothing to delete when the service doesn't answer with the job's URL" do
      expect_request("POST", "/tap/async", &respond(&1, 200, "text/xml", "<job/>"))

      assert submit() ==
               {:error,
                %Error{
                  type: :decode_error,
                  message: "expected a redirect to the new job, got text/xml",
                  status: 200
                }}

      expect_request("POST", "/tap/async", &Plug.Conn.send_resp(&1, 303, ""))

      assert submit() ==
               {:error,
                %Error{type: :http_error, message: "no Location for the new job", status: 303}}
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

  describe "wait/2" do
    test "asks the service to answer when the phase changes, until the job stops" do
      expect_request("GET", "/tap/async/42", &phase_document(&1, "EXECUTING"))
      expect_request("GET", "/tap/async/42", &phase_document(&1, "COMPLETED"))

      assert wait(job(:queued)) ==
               {:ok,
                %Job{
                  url: @job_url,
                  phase: :completed,
                  format: :votable,
                  error_summary: nil,
                  result_url: @job_url <> "/results/result"
                }}

      # UWS 1.1 §2.2.1.2: WAIT is the most seconds the service may block.
      assert_received {:request, "GET", "/tap/async/42", %{"WAIT" => "30"}}
      assert_received {:request, "GET", "/tap/async/42", %{"WAIT" => "30"}}
    end

    test "keeps asking while the service may move the job on, as it does a suspended or unknown one" do
      for phase <- ["SUSPENDED", "UNKNOWN", "EXECUTING", "COMPLETED"] do
        expect_request("GET", "/tap/async/42", &phase_document(&1, phase))
      end

      assert {:ok, %Job{phase: :completed}} = wait(job(:queued))
    end

    test "stops at a phase the job won't leave without the client (UWS 1.1 §2.1.3)" do
      for {name, phase} <- [
            {"COMPLETED", :completed},
            {"ERROR", :error},
            {"ABORTED", :aborted},
            {"ARCHIVED", :archived},
            {"PENDING", :pending},
            {"HELD", :held}
          ] do
        expect_request("GET", "/tap/async/42", &phase_document(&1, name))
        assert {:ok, %Job{phase: ^phase}} = wait(job(:executing))
      end
    end

    test "reads a job that has stopped once, without WAIT, which GAVO would block a PENDING job for" do
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "pending.xml"))

      assert {:ok, %Job{phase: :pending}} = wait(job(:pending))
      assert_received {:request, "GET", "/tap/async/42", params}
      refute Map.has_key?(params, "WAIT")
    end

    test "reads the error summary of a job that stops in ERROR" do
      expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", "error.xml"))

      assert {:ok, %Job{phase: :error, error_summary: "Cannot parse query" <> _rest}} =
               wait(job(:executing))
    end

    test "pauses before asking again a service that answers before the WAIT, as the Gaia archive does" do
      stub_requests(&job_document(&1, "gaia", "executing.xml"))

      started = System.monotonic_time(:millisecond)
      assert {:error, %Error{type: :timeout}} = wait(job(:executing), timeout: 1_200)
      elapsed = System.monotonic_time(:millisecond) - started

      # Without a pause, it would ask hundreds of times. It asks with the
      # seconds left, then pauses a second, asks again and pauses no longer
      # than the time left.
      assert_received {:request, "GET", "/tap/async/42", %{"WAIT" => "1"}}
      assert_received {:request, "GET", "/tap/async/42", %{"WAIT" => "0"}}
      refute_received {:request, _method, _path, _params}
      assert elapsed in 1_200..1_700
    end

    test "returns a :timeout error, without asking, once the time has run out" do
      assert wait(job(:executing), timeout: 0) ==
               {:error,
                %Error{
                  type: :timeout,
                  message: "the job is still EXECUTING after 0 ms",
                  status: nil
                }}
    end

    test "returns the error a request gives" do
      # Req tries a GET again after a transport error or a 5xx, so a 403.
      expect_request("GET", "/tap/async/42", &respond(&1, 403, "text/html", ""))

      assert {:error, %Error{type: :http_error, status: 403}} = wait(job(:executing))
    end

    test "raises on an option it doesn't know or can't use" do
      assert_raise ArgumentError, ~r/unknown keys \[:format\]/, fn ->
        wait(job(:executing), format: :csv)
      end

      for timeout <- [-1, 1.5, "1000"] do
        assert_raise ArgumentError, ~r/:timeout to be a non-negative integer or :infinity/, fn ->
          wait(job(:executing), timeout: timeout)
        end
      end
    end
  end

  describe "result/2" do
    test "reads the result of a COMPLETED job in the format it was submitted with" do
      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        respond(conn, 200, "application/x-votable+xml", fixture("gavo", "hipparcos.xml"))
      end)

      assert {:ok, %Result{columns: columns, rows: [[1 | _values] | _rows], overflow: false}} =
               result(completed(:votable))

      assert columns == ["hipno", "ra", "dec", "vmag", "parallax", "SpType"]

      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        respond(conn, 200, "text/csv;header=present", fixture("gavo", "hipparcos.csv"))
      end)

      assert {:ok, %Result{rows: [["1" | _values] | _rows], fields: nil}} =
               result(completed(:csv))
    end

    test "reads it as query/3 reads a sync result, errors included" do
      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        respond(conn, 200, "application/x-votable+xml", fixture("gavo", "hipparcos.xml"))
      end)

      assert {:error, %Error{type: :decode_error, message: "expected text/csv, got " <> _rest}} =
               result(completed(:csv))

      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        respond(conn, 200, "text/xml", fixture("gaia", "syntax_error.xml"))
      end)

      assert {:error, %Error{type: :service_error, status: 200}} = result(completed(:votable))
    end

    test "reads an http:// result on the job's host with https://, as GAVO lists it" do
      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        assert conn.scheme == :https
        respond(conn, 200, "text/csv", fixture("gavo", "hipparcos.csv"))
      end)

      job = %{completed(:csv) | result_url: "http://tap.example.org/tap/async/42/results/result"}
      assert {:ok, %Result{}} = result(job)
    end

    test "doesn't read an http:// result on another host for a job at an https:// URL" do
      job = %{completed(:csv) | result_url: "http://results.example.org/42.csv"}

      assert result(job) ==
               {:error,
                %Error{
                  type: :decode_error,
                  message:
                    "the job is at an https:// URL and lists its result at an http:// one: " <>
                      "http://results.example.org/42.csv",
                  status: nil
                }}
    end

    test "keeps credentials from another host, as Req does on a redirect, but not other headers" do
      # CADC lists its results on ws-cadc.canfar.net.
      job = %{completed(:csv) | result_url: "https://results.example.org/42.csv"}

      for req_options <- [
            [headers: [{"Authorization", "Bearer secret"}, {"x-request-id", "42"}]],
            [headers: %{"x-request-id" => "42"}, auth: {:bearer, "secret"}]
          ] do
        expect_request("GET", "/42.csv", fn conn ->
          assert conn.host == "results.example.org"
          assert Plug.Conn.get_req_header(conn, "authorization") == []
          assert Plug.Conn.get_req_header(conn, "x-request-id") == ["42"]
          respond(conn, 200, "text/csv", fixture("gavo", "hipparcos.csv"))
        end)

        assert {:ok, %Result{}} = result(job, req_options: req_options ++ req_options())
      end

      # They go to the job's host.
      expect_request("GET", "/tap/async/42/results/result", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret"]
        respond(conn, 200, "text/csv", fixture("gavo", "hipparcos.csv"))
      end)

      assert {:ok, %Result{}} =
               result(completed(:csv), req_options: [auth: {:bearer, "secret"}] ++ req_options())
    end

    test "gives a :service_error naming the phase of a job that stopped without a result" do
      for {phase, summary, message} <- [
            {:error, "Field query: No such field known",
             "the job is ERROR: Field query: No such field known"},
            {:aborted, nil, "the job is ABORTED"},
            {:archived, nil, "the job is ARCHIVED"},
            {:held, nil, "the job is HELD"},
            {:pending, nil, "the job is PENDING"}
          ] do
        job = %{job(phase) | error_summary: summary}

        assert result(job) ==
                 {:error, %Error{type: :service_error, message: message, status: nil}}
      end
    end

    test "is a :decode_error for a COMPLETED job without a result" do
      assert {:error,
              %Error{type: :decode_error, message: "the job is COMPLETED and lists no result"}} =
               result(job(:completed))
    end

    test "raises for a job that hasn't stopped" do
      for phase <- [:queued, :executing, :suspended, :unknown] do
        assert_raise ArgumentError, ~r/wait for it to stop with SpaceTAP.Job.wait\/2/, fn ->
          result(job(phase))
        end
      end
    end

    test "raises on an option it doesn't know" do
      assert_raise ArgumentError, ~r/unknown keys \[:format\]/, fn ->
        result(completed(:csv), format: :votable)
      end
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
            else: respond(conn, 200, "text/xml", fixture("koa", "jobs/completed.xml"))
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

  defp wait(job, opts \\ []) do
    Job.wait(job, Keyword.put_new(opts, :req_options, @req_options))
  end

  defp result(job, opts \\ []) do
    Job.result(job, Keyword.put_new(opts, :req_options, @req_options))
  end

  defp completed(format) do
    %Job{
      url: @job_url,
      phase: :completed,
      format: format,
      result_url: @job_url <> "/results/result"
    }
  end

  defp job(phase), do: %Job{url: @job_url, phase: phase, format: :votable}

  defp user_agent, do: "space_tap/" <> to_string(Application.spec(:space_tap, :vsn))
end
