defmodule SpaceTAP.Test.AsyncService do
  @moduledoc false

  # Stands in for a TAP service in the unit tests of async queries, through
  # Req.Test and the stub name SpaceTAP.Job, which the tests pass to Req in
  # `req_options/0`. Each request the service gets is sent to the test
  # process as {:request, method, path, params}, with the parameters of its
  # URL and form decoded. A test that needs the options of a request, which
  # Req's plug doesn't see, passes this module as Req's adapter instead, in
  # `adapter: SpaceTAP.Test.AsyncService`: see `run/1`.

  import ExUnit.Assertions

  @fixtures Path.expand("../fixtures", __DIR__)

  # The result of a COMPLETED job at .../42, at <job>/results/result.
  @results ~s(<results><result id="result" href="42/results/result"/></results>)

  @spec req_options() :: keyword()
  def req_options, do: [plug: {Req.Test, SpaceTAP.Job}]

  # The service as Req's adapter, the step that makes the request, below
  # the others: the request arrives with its options, such as the
  # :receive_timeout Req's plug doesn't apply. Req runs the adapter in the
  # process that sends the request, the test's, so the request is sent to
  # it as {:request, %Req.Request{}}, and answered with a COMPLETED job.
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t()}
  def run(request) do
    send(self(), {:request, request})

    response =
      Req.Response.new(
        status: 200,
        headers: [{"content-type", "text/xml"}],
        body: "<job><phase>COMPLETED</phase>#{@results}</job>"
      )

    {request, response}
  end

  # The next request the service gets: checks its method and path, and
  # answers with respond.
  @spec expect_request(String.t(), String.t(), (Plug.Conn.t() -> Plug.Conn.t())) :: term()
  def expect_request(method, path, respond) do
    test = self()

    Req.Test.expect(SpaceTAP.Job, fn conn ->
      assert {conn.method, conn.request_path} == {method, path}
      send_request(test, conn, respond)
    end)
  end

  # Every request the service gets, however many.
  @spec stub_requests((Plug.Conn.t() -> Plug.Conn.t())) :: term()
  def stub_requests(respond) do
    test = self()
    Req.Test.stub(SpaceTAP.Job, &send_request(test, &1, respond))
  end

  @spec respond(Plug.Conn.t(), pos_integer(), String.t(), binary()) :: Plug.Conn.t()
  def respond(conn, status, content_type, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", content_type)
    |> Plug.Conn.send_resp(status, body)
  end

  @spec redirect(Plug.Conn.t(), pos_integer(), String.t()) :: Plug.Conn.t()
  def redirect(conn, status, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(status, "")
  end

  # A job document from the fixtures of a service.
  @spec job_document(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def job_document(conn, service, name),
    do: respond(conn, 200, "text/xml", fixture(service, Path.join("jobs", name)))

  # A job document with only a phase, and for COMPLETED the result.
  @spec phase_document(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def phase_document(conn, phase) do
    results = if phase == "COMPLETED", do: @results, else: ""
    respond(conn, 200, "text/xml", "<job><phase>#{phase}</phase>#{results}</job>")
  end

  @spec fixture(String.t(), String.t()) :: binary()
  def fixture(service, name), do: File.read!(Path.join([@fixtures, service, name]))

  defp send_request(test, conn, respond) do
    {:ok, form, conn} = Plug.Conn.read_body(conn)
    params = Map.merge(URI.decode_query(conn.query_string), URI.decode_query(form))
    send(test, {:request, conn.method, conn.request_path, params})
    respond.(conn)
  end
end
