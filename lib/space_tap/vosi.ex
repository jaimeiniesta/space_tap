defmodule SpaceTAP.VOSI do
  @moduledoc false

  # Reads two VOSI documents (VOSI 1.1): the capabilities of a service, for
  # the URL of its availability, and the availability itself, which
  # read_availability/2 asks the service for, one after the other. An
  # element counts by its role, as SpaceTAP.XML reads it, so only where the
  # standard puts it.

  alias SpaceTAP.{Availability, Error, HTTP, XML}

  @behaviour XML

  # IVOA identifiers are case insensitive.
  @availability_id "ivo://ivoa.net/std/vosi#availability"

  @availability_roles %{
    "available" => :available,
    "upSince" => :up_since,
    "downAt" => :down_at,
    "backAt" => :back_at,
    "note" => :note
  }

  # The availability of the service at `service_url`, with the caller's Req
  # options. Its URL comes from the capabilities, at /capabilities under the
  # service URL (DALI 1.1 §2.5), and is read by the rule for listed URLs
  # from the service, which is where the credentials belong (ADR 0014, ADR
  # 0015). A relative URL in the capabilities is relative to where the
  # redirects led (RFC 3986 §5.1.3).
  @spec read_availability(String.t(), keyword()) ::
          {:ok, Availability.t()} | {:error, Error.t()}
  def read_availability(service_url, req_options) do
    capabilities_url = String.trim_trailing(service_url, "/") <> "/capabilities"
    {capabilities_url, response} = HTTP.fetch(req_options, capabilities_url)

    with {:ok, listed_url} <- HTTP.read_vosi(response, &availability_url/1),
         listed_url = capabilities_url |> URI.merge(listed_url) |> URI.to_string(),
         {:ok, url, req_options} <-
           HTTP.listed(req_options, service_url, listed_url, "the service lists its availability") do
      req_options |> HTTP.run(method: :get, url: url) |> HTTP.read_vosi(&availability/1)
    end
  end

  # The URL of the availability, the accessURL of the capability whose
  # standardID is that of VOSI availability (VOSI 1.1 §4): DALI 1.1 §2
  # lets a service put it anywhere, and GAVO does.
  @spec availability_url(binary()) :: {:ok, String.t()} | {:error, String.t()}
  def availability_url(xml) do
    with {:ok, document} <- parse(xml), do: access_url(document)
  end

  # `available` is required, and the rest optional (VOSI 1.1 §3.2).
  @spec availability(binary()) :: {:ok, Availability.t()} | {:error, String.t()}
  def availability(xml) do
    with {:ok, document} <- parse(xml), do: decode_availability(document)
  end

  @impl XML
  def role(nil, "capabilities", _attributes), do: :capabilities

  def role(:capabilities, "capability", attributes) do
    id = XML.attribute(attributes, "standardID")
    if id && String.downcase(id) == @availability_id, do: :availability_capability, else: :other
  end

  def role(:availability_capability, "interface", _attributes), do: :interface
  def role(:interface, "accessURL", _attributes), do: :access_url
  def role(nil, "availability", _attributes), do: :availability
  def role(:availability, name, _attributes), do: Map.get(@availability_roles, name, :other)
  def role(_parent, _name, _attributes), do: :other

  @impl XML
  def text_roles, do: [:access_url, :available, :up_since, :down_at, :back_at, :note]

  # The root says which of the two documents this is.
  @impl XML
  def start(root, _attributes, document) when root in [:capabilities, :availability],
    do: %{document | root: root}

  def start(_role, _attributes, document), do: document

  # The values of each role with text, trimmed, in the order they came.
  @impl XML
  def finish(_role, nil, document), do: document

  def finish(role, text, document) do
    value = String.trim(text)
    %{document | values: Map.update(document.values, role, [value], &(&1 ++ [value]))}
  end

  #####################
  # Private functions #
  #####################

  defp parse(xml), do: XML.parse(xml, __MODULE__, %{root: nil, values: %{}})

  defp access_url(%{root: :capabilities, values: %{access_url: [url | _urls]}}), do: {:ok, url}

  defp access_url(%{root: :capabilities}),
    do:
      {:error,
       "the capabilities document lists no ivo://ivoa.net/std/VOSI#availability capability"}

  defp access_url(_document), do: {:error, "expected a VOSI capabilities document"}

  defp decode_availability(%{root: :availability, values: %{available: [text | _]} = values}) do
    with {:ok, available} <- boolean(text) do
      {:ok,
       %Availability{
         available: available,
         up_since: first(values, :up_since),
         down_at: first(values, :down_at),
         back_at: first(values, :back_at),
         notes: values |> Map.get(:note, []) |> Enum.reject(&(&1 == ""))
       }}
    end
  end

  defp decode_availability(%{root: :availability}),
    do: {:error, "the availability document has no available element"}

  defp decode_availability(_document), do: {:error, "expected a VOSI availability document"}

  defp first(values, role), do: values |> Map.get(role, []) |> List.first()

  # The lexical forms of an xsd:boolean.
  defp boolean(text) when text in ["true", "1"], do: {:ok, true}
  defp boolean(text) when text in ["false", "0"], do: {:ok, false}

  defp boolean(text),
    do: {:error, "the availability document says available is #{inspect(text)}, not a boolean"}
end
