defmodule SpaceTAP.VOSI do
  @moduledoc false

  # Reads two VOSI documents (VOSI 1.1): the capabilities of a service, for
  # the URL of its availability, and the availability itself. As in
  # SpaceTAP.UWS, names are matched without their namespace prefix, which
  # changes from one service to another, and an element only counts where
  # the standard puts it.

  @behaviour Saxy.Handler

  alias SpaceTAP.{Availability, XML}

  # IVOA identifiers are case insensitive.
  @availability_id "ivo://ivoa.net/std/vosi#availability"

  @text_roles [:access_url, :available, :up_since, :down_at, :back_at, :note]

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

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, %{stack: stack} = document) do
    role = role(parent(stack), XML.local_name(name), attributes)
    document = %{document | stack: [role | stack], text: []}
    {:ok, if(stack == [], do: %{document | root: role}, else: document)}
  end

  def handle_event(:characters, chars, %{stack: [role | _roles], text: text} = document)
      when role in @text_roles do
    {:ok, %{document | text: [text, chars]}}
  end

  def handle_event(:end_element, _name, %{stack: [role | roles]} = document)
      when role in @text_roles do
    value = document.text |> IO.iodata_to_binary() |> String.trim()
    values = Map.update(document.values, role, [value], &(&1 ++ [value]))
    {:ok, %{document | stack: roles, values: values}}
  end

  def handle_event(:end_element, _name, %{stack: [_role | roles]} = document) do
    {:ok, %{document | stack: roles}}
  end

  def handle_event(_event, _data, document), do: {:ok, document}

  #####################
  # Private functions #
  #####################

  defp parse(xml), do: XML.parse(xml, __MODULE__, %{stack: [], text: [], root: nil, values: %{}})

  defp parent([role | _roles]), do: role
  defp parent([]), do: nil

  defp role(nil, "capabilities", _attributes), do: :capabilities

  defp role(:capabilities, "capability", attributes) do
    id = Enum.find_value(attributes, fn {key, value} -> key == "standardID" && value end)
    if id && String.downcase(id) == @availability_id, do: :availability_capability, else: :other
  end

  defp role(:availability_capability, "interface", _attributes), do: :interface
  defp role(:interface, "accessURL", _attributes), do: :access_url
  defp role(nil, "availability", _attributes), do: :availability
  defp role(:availability, name, _attributes), do: Map.get(@availability_roles, name, :other)
  defp role(_parent, _name, _attributes), do: :other

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
