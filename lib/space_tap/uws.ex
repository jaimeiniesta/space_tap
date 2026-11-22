defmodule SpaceTAP.UWS do
  @moduledoc false

  # Reads a job document: the XML a TAP service returns for the URL of an
  # async job, which TAP 1.1 §2.2 runs as a UWS job (UWS 1.1 §2.2.2.2).
  # SpaceTAP reads three things from it: the phase, the message of the error
  # summary, and where the result is.
  #
  # Services write it in different shapes. NED and ESO use a default
  # namespace instead of the uws prefix, Gaia says version 1.0 and IRSA, the
  # NASA Exoplanet Archive and KOA say none, and their times come in
  # different zones or in none. So only what SpaceTAP uses is required, and
  # nothing else is checked: an element counts by its role, as SpaceTAP.XML
  # reads it, and neither the namespace nor the version is read.

  alias SpaceTAP.{Job, XML}

  @behaviour XML

  @type job :: %{phase: Job.phase(), error_summary: String.t() | nil, result: String.t() | nil}

  # The ten phases of UWS 1.1 §2.1.3, by the name the job document gives them.
  @phases Map.new(
            ~w(pending queued executing completed error aborted unknown held suspended archived)a,
            &{&1 |> Atom.to_string() |> String.upcase(), &1}
          )

  @spec parse(binary()) :: {:ok, job()} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    document = %{job: false, phases: [], messages: [], results: []}

    with {:ok, document} <- XML.parse(xml, __MODULE__, document), do: decode(document)
  end

  # An element only counts where UWS 1.1 §2.2.2.2 puts it: a phase is the
  # job's only as a child of the job.
  @impl XML
  def role(nil, "job", _attributes), do: :job
  def role(:job, "phase", _attributes), do: :phase
  def role(:job, "errorSummary", _attributes), do: :error_summary
  def role(:error_summary, "message", _attributes), do: :message
  def role(:job, "results", _attributes), do: :results

  # A job may list other results besides the one TAP names result (TAP 1.1
  # §2.2), such as the diag and rowcount of CADC, so the result is found by
  # its id.
  def role(:results, "result", attributes) do
    if XML.attribute(attributes, "id") == "result", do: :result, else: :other
  end

  def role(_parent, _name, _attributes), do: :other

  @impl XML
  def text_roles, do: [:phase, :message]

  @impl XML
  def start(:job, _attributes, document), do: %{document | job: true}

  # The href of a result is an XLink attribute, usually written xlink:href.
  def start(:result, attributes, document) do
    %{document | results: [XML.attribute(attributes, "href") | document.results]}
  end

  def start(_role, _attributes, document), do: document

  # Gaia writes its messages in CDATA sections and KOA with character
  # references; Saxy hands both over as text.
  @impl XML
  def finish(:phase, text, document),
    do: %{document | phases: [String.trim(text) | document.phases]}

  def finish(:message, text, document),
    do: %{document | messages: [String.trim(text) | document.messages]}

  def finish(_role, _text, document), do: document

  #####################
  # Private functions #
  #####################

  defp decode(%{job: false}), do: {:error, "expected a UWS job document"}

  defp decode(document) do
    with {:ok, phase} <- one(document.phases, "phase"),
         {:ok, phase} <- phase(phase),
         {:ok, message} <- one(document.messages, "error summary message"),
         {:ok, result} <- one(document.results, "result") do
      job(phase, message, result)
    end
  end

  defp one([], "phase"), do: {:error, "the job document has no phase"}
  defp one([], _what), do: {:ok, nil}
  defp one([value], _what), do: {:ok, value}
  defp one(_values, what), do: {:error, "the job document has more than one #{what}"}

  defp phase(phase) do
    case Map.fetch(@phases, phase) do
      {:ok, phase} -> {:ok, phase}
      :error -> {:error, "the job document has an unknown phase: #{inspect(phase)}"}
    end
  end

  # TAP 1.1 §2.2 requires the result of a job that ran: "the result resource
  # must exist". An empty or blank message or href says nothing.
  defp job(phase, message, result) do
    case present(result) do
      nil when phase == :completed ->
        {:error, "the job is COMPLETED and its document lists no result"}

      result ->
        {:ok, %{phase: phase, error_summary: present(message), result: result}}
    end
  end

  defp present(nil), do: nil
  defp present(value), do: if(String.trim(value) == "", do: nil, else: value)
end
