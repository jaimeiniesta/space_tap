defmodule SpaceTAPAvailabilityTest do
  # SpaceTAP.availability/2, which finds the availability URL in
  # /capabilities and reads the availability document there. The fixtures
  # are what each service sent on 2026-11-18. Req.Test answers for any
  # host, so each test uses the service URL of its fixtures.
  use ExUnit.Case, async: true

  alias SpaceTAP.{Availability, Error}

  @req_options [plug: {Req.Test, SpaceTAP}]
  @fixtures Path.expand("fixtures", __DIR__)

  test "reads the availability URL from /capabilities and the availability there" do
    stub_fixtures("irsa")

    assert availability("https://irsa.ipac.caltech.edu/TAP/") ==
             {:ok,
              %Availability{
                available: true,
                up_since: nil,
                down_at: nil,
                back_at: nil,
                notes: ["services work properly."]
              }}

    assert_received {:request, capabilities}
    assert {capabilities.method, capabilities.request_path} == {"GET", "/TAP/capabilities"}
    assert_received {:request, availability}
    assert {availability.method, availability.request_path} == {"GET", "/TAP/availability"}
  end

  test "reads upSince, and the URL of a service that lists it with spaces around it" do
    stub_fixtures("mast")

    assert {:ok, %Availability{available: true, up_since: "2026-11-16T04:36:37.069Z", notes: []}} =
             availability("https://mast.stsci.edu/vo-tap/api/v0.1/caom")

    stub_fixtures("ned")

    assert {:ok, %Availability{available: true, notes: ["TAP service available."]}} =
             availability("https://ned.ipac.caltech.edu/tap")
  end

  # GAVO lists http://dc.g-vo.org/__system__/tap/run/availability.
  test "reads an http:// availability URL on the service's host with https://" do
    stub_fixtures("gavo")

    assert {:ok, %Availability{available: true, up_since: "2026-10-30T12:22:56Z"}} =
             availability("https://dc.g-vo.org/tap")

    assert_received {:request, %Plug.Conn{request_path: "/tap/capabilities"}}
    assert_received {:request, conn}
    assert {conn.scheme, conn.host, conn.port} == {:https, "dc.g-vo.org", 443}
    assert conn.request_path == "/__system__/tap/run/availability"
  end

  test "is a :decode_error, with no request, for an http:// availability URL on another host" do
    stub_documents(capabilities("http://status.example.org/availability"), availability_xml(true))

    assert {:error, %Error{type: :decode_error, message: message}} =
             availability("https://tap.example.org/tap")

    assert message =~ "http://status.example.org/availability"
    assert_received {:request, %Plug.Conn{request_path: "/tap/capabilities"}}
    refute_received {:request, _conn}
  end

  test "doesn't send the authorization header to an availability URL on another host" do
    stub_documents(
      capabilities("https://status.example.org/availability"),
      availability_xml(true)
    )

    assert {:ok, %Availability{available: true}} =
             availability("https://tap.example.org/tap",
               req_options: [headers: [authorization: "Bearer secret"]] ++ @req_options
             )

    assert_received {:request, capabilities}
    assert Plug.Conn.get_req_header(capabilities, "authorization") == ["Bearer secret"]
    assert_received {:request, availability}
    assert availability.host == "status.example.org"
    assert Plug.Conn.get_req_header(availability, "authorization") == []
  end

  test "resolves a relative availability URL against /capabilities" do
    stub_documents(capabilities("status/availability"), availability_xml(true))

    assert {:ok, %Availability{}} = availability("https://tap.example.org/tap")
    assert_received {:request, %Plug.Conn{request_path: "/tap/capabilities"}}
    assert_received {:request, %Plug.Conn{request_path: "/tap/status/availability"}}
  end

  # KOA sends both documents with no Content-Type.
  test "reads documents with no Content-Type as XML" do
    stub_fixtures("koa", nil)

    assert {:ok, %Availability{available: true, notes: ["TAP service available."]}} =
             availability("https://koa.ipac.caltech.edu/TAP")
  end

  # IVOA identifiers are case insensitive.
  test "finds the availability capability whatever the case of its standardID" do
    capabilities =
      String.replace(
        capabilities("https://tap.example.org/tap/availability"),
        "VOSI#availability",
        "vosi#Availability"
      )

    stub_documents(capabilities, availability_xml(true))

    assert {:ok, %Availability{available: true}} = availability("https://tap.example.org/tap")
  end

  test "is a :decode_error when /capabilities lists no availability" do
    stub_documents(
      ~s(<capabilities><capability standardID="ivo://ivoa.net/std/TAP"/></capabilities>),
      availability_xml(true)
    )

    assert {:error, %Error{type: :decode_error, message: message, status: 200}} =
             availability("https://tap.example.org/tap")

    assert message =~ "lists no ivo://ivoa.net/std/VOSI#availability capability"
  end

  # The body decides before the status (ADR 0001).
  test "reads an availability document that says the service is down, whatever its status" do
    document = """
    <availability xmlns="http://www.ivoa.net/xml/VOSIAvailability/v1.0">
      <available>false</available>
      <downAt>2026-11-25T08:00:00Z</downAt>
      <backAt>2026-12-02T08:00:00Z</backAt>
      <note>Closed for Gaia DR4.</note>
      <note>Queries are refused.</note>
    </availability>
    """

    stub_documents(capabilities("https://tap.example.org/tap/availability"), document,
      availability_status: 503
    )

    assert availability("https://tap.example.org/tap") ==
             {:ok,
              %Availability{
                available: false,
                up_since: nil,
                down_at: "2026-11-25T08:00:00Z",
                back_at: "2026-12-02T08:00:00Z",
                notes: ["Closed for Gaia DR4.", "Queries are refused."]
              }}
  end

  test "reads available as an xsd:boolean" do
    for {text, available} <- [{"true", true}, {" 1 ", true}, {"false", false}, {"0", false}] do
      stub_documents(
        capabilities("https://tap.example.org/tap/availability"),
        availability_xml(text)
      )

      assert {:ok, %Availability{available: ^available}} =
               availability("https://tap.example.org/tap")
    end
  end

  test "is a :decode_error when available is missing or isn't a boolean" do
    for document <- [
          ~s(<availability><note>up</note></availability>),
          availability_xml("yes"),
          ~s(<capabilities/>)
        ] do
      stub_documents(capabilities("https://tap.example.org/tap/availability"), document)

      assert {:error, %Error{type: :decode_error}} = availability("https://tap.example.org/tap")
    end
  end

  # SIMBAD answered /capabilities with a 404 HTML page while CDS was down.
  test "is an :http_error for an HTML page with an error status" do
    stub_documents("<html><body>Page unavailable</body></html>", "",
      capabilities_status: 404,
      content_type: "text/html"
    )

    assert {:error, %Error{type: :http_error, status: 404}} =
             availability("https://tap.example.org/tap")
  end

  test "is a :decode_error for a successful response that isn't XML" do
    stub_documents("<html><body>Archive closed</body></html>", "", content_type: "text/html")

    assert {:error, %Error{type: :decode_error, status: 200, message: message}} =
             availability("https://tap.example.org/tap")

    assert message =~ "text/html"
  end

  test "raises for an unknown option" do
    assert_raise ArgumentError, ~r/unknown keys \[:format\]/, fn ->
      SpaceTAP.availability("https://tap.example.org/tap", format: :votable)
    end
  end

  #####################
  # Private functions #
  #####################

  defp availability(service_url, opts \\ [req_options: @req_options]),
    do: SpaceTAP.availability(service_url, opts)

  defp capabilities(access_url) do
    """
    <vosi:capabilities xmlns:vosi="http://www.ivoa.net/xml/VOSICapabilities/v1.0">
      <capability standardID="ivo://ivoa.net/std/TAP">
        <interface><accessURL use="base">https://tap.example.org/tap</accessURL></interface>
      </capability>
      <capability standardID="ivo://ivoa.net/std/VOSI#availability">
        <interface><accessURL use="full">#{access_url}</accessURL></interface>
      </capability>
    </vosi:capabilities>
    """
  end

  defp availability_xml(available) do
    ~s(<availability xmlns="http://www.ivoa.net/xml/VOSIAvailability/v1.0"><available>#{available}</available></availability>)
  end

  defp fixture(service, name), do: File.read!(Path.join([@fixtures, service, name]))

  # Stands in for a service with the documents of its fixtures.
  defp stub_fixtures(service, content_type \\ "text/xml") do
    stub_documents(fixture(service, "capabilities.xml"), fixture(service, "availability.xml"),
      content_type: content_type
    )
  end

  # Answers /capabilities with the first document and any other path with
  # the second, with the status of each and the Content-Type given (none
  # for nil), and sends each request to the test process.
  defp stub_documents(capabilities, availability, opts \\ []) do
    test = self()
    content_type = Keyword.get(opts, :content_type, "text/xml")

    Req.Test.stub(SpaceTAP, fn conn ->
      send(test, {:request, conn})

      {body, status} =
        if String.ends_with?(conn.request_path, "/capabilities"),
          do: {capabilities, Keyword.get(opts, :capabilities_status, 200)},
          else: {availability, Keyword.get(opts, :availability_status, 200)}

      conn
      |> put_content_type(content_type)
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp put_content_type(conn, nil), do: conn
  defp put_content_type(conn, type), do: Plug.Conn.put_resp_header(conn, "content-type", type)
end
