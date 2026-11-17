defmodule SpaceTAPAsyncQueryTest do
  use ExUnit.Case, async: true

  import SpaceTAP.Test.AsyncService

  alias SpaceTAP.{Error, Result}

  @service_url "https://tap.example.org/tap"
  @job_url "https://tap.example.org/tap/async/42"
  @adql "SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main"

  # Req logs each redirect, and a job comes after one.
  @moduletag :capture_log

  setup {Req.Test, :verify_on_exit!}

  describe "async_query/3" do
    test "submits the query as a job, waits for it, reads its result and deletes the job" do
      expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "pending.xml"))
      expect_request("POST", "/tap/async/42/phase", &redirect(&1, 303, @job_url))
      expect_request("GET", "/tap/async/42", &phase_document(&1, "EXECUTING"))
      expect_request("GET", "/tap/async/42", &phase_document(&1, "COMPLETED"))
      expect_votable_result()
      expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))

      assert {:ok, %Result{columns: ["hipno" | _columns], rows: rows}} =
               async_query(format: :votable, maxrec: 5)

      assert length(rows) == 5

      assert_received {:request, "POST", "/tap/async",
                       %{"FORMAT" => "votable", "MAXREC" => "5", "QUERY" => @adql}}

      assert_received {:request, "POST", "/tap/async/42/phase", %{"PHASE" => "RUN"}}
      assert_received {:request, "GET", "/tap/async/42", %{"WAIT" => "30"}}
    end

    test "gives the :service_error of a job that fails, and deletes it" do
      expect_submit("executing.xml")
      expect_request("GET", "/tap/async/42", &job_document(&1, "gavo", "error.xml"))
      expect_delete()

      assert async_query() ==
               {:error,
                %Error{
                  type: :service_error,
                  message:
                    "the job is ERROR: Field query: No such field known: column 'nosuchcolumn' " <>
                      "could not be located in table metadata",
                  status: nil
                }}
    end

    test "deletes the job, which stops it, when the time runs out" do
      expect_submit("executing.xml")
      expect_delete()

      assert {:error, %Error{type: :timeout, message: "the job is still EXECUTING after 0 ms"}} =
               async_query(timeout: 0)
    end

    test "deletes the job when its result can't be read" do
      expect_submit("executing.xml")
      expect_request("GET", "/tap/async/42", &phase_document(&1, "COMPLETED"))
      expect_request("GET", "/tap/async/42/results/result", &respond(&1, 404, "text/html", ""))
      expect_delete()

      assert {:error, %Error{type: :http_error, status: 404}} = async_query()
    end

    test "returns the result when the job can't be deleted" do
      expect_submit("executing.xml")
      expect_request("GET", "/tap/async/42", &phase_document(&1, "COMPLETED"))
      expect_votable_result()
      expect_request("DELETE", "/tap/async/42", &respond(&1, 404, "text/html", ""))
      expect_request("POST", "/tap/async/42", &respond(&1, 404, "text/html", ""))

      assert {:ok, %Result{}} = async_query(format: :votable)
    end

    test "has nothing to delete when the service doesn't create the job" do
      expect_request("POST", "/tap/async", fn conn ->
        respond(conn, 400, "text/xml", fixture("gaia", "syntax_error.xml"))
      end)

      assert {:error, %Error{type: :service_error, status: 400}} = async_query()
    end

    test "raises before it creates a job for an option it doesn't know or can't use" do
      assert_raise ArgumentError, ~r/unknown keys \[:wait\]/, fn -> async_query(wait: 10) end

      assert_raise ArgumentError, ~r/:timeout to be a non-negative integer or :infinity/, fn ->
        async_query(timeout: -1)
      end

      assert_raise ArgumentError, ~r/:format to be :csv or :votable/, fn ->
        async_query(format: :fits)
      end
    end
  end

  defp async_query(opts \\ []) do
    SpaceTAP.async_query(@service_url, @adql, Keyword.put_new(opts, :req_options, req_options()))
  end

  # A job the service has started by the time submit/3 reads it.
  defp expect_submit(document) do
    expect_request("POST", "/tap/async", &redirect(&1, 303, @job_url))
    expect_request("GET", "/tap/async/42", &job_document(&1, "gaia", document))
  end

  defp expect_votable_result do
    expect_request("GET", "/tap/async/42/results/result", fn conn ->
      respond(conn, 200, "application/x-votable+xml", fixture("gavo", "hipparcos.xml"))
    end)
  end

  defp expect_delete do
    expect_request("DELETE", "/tap/async/42", &redirect(&1, 303, @service_url <> "/async"))
  end
end
