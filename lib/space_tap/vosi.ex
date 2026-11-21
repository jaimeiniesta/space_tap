defmodule SpaceTAP.VOSI do
  @moduledoc false

  # Reads two VOSI documents (VOSI 1.1): the capabilities of a service, for
  # the URL of its availability, and the availability itself. An element
  # counts by its role, as SpaceTAP.XML reads it, so only where the standard
  # puts it.

  alias SpaceTAP.{Availability, XML}

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
