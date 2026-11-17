defmodule SpaceTAP.UWS do
  @moduledoc false

  # Reads a job document: the XML a TAP service returns for the URL of an
  # async job, which TAP 1.1 §2.2 runs as a UWS job (UWS 1.1 §2.2.1.1).
  # SpaceTAP reads three things from it: the phase, the message of the error
  # summary, and where the result is.
  #
  # Services write it in different shapes. NED and ESO use a default
  # namespace instead of the uws prefix, Gaia says version 1.0 and IRSA, the
  # NASA Exoplanet Archive and KOA say none, and their times come in
  # different zones or in none. So only what SpaceTAP uses is required, and
  # nothing else is checked: names are matched without their prefix, as in
  # SpaceTAP.VOTable, and neither the namespace nor the version is read.

  @behaviour Saxy.Handler

  alias SpaceTAP.XML

  @typedoc "One of the ten phases of a UWS job (UWS 1.1 §2.1.3)."
  @type phase ::
          :pending
          | :queued
          | :executing
          | :completed
          | :error
          | :aborted
          | :unknown
          | :held
          | :suspended
          | :archived

  @type job :: %{phase: phase(), error_summary: String.t() | nil, result: String.t() | nil}

  @phases Map.new(
            ~w(pending queued executing completed error aborted unknown held suspended archived)a,
            &{&1 |> Atom.to_string() |> String.upcase(), &1}
          )

  # The elements whose text is read.
  @text_roles [:phase, :message]

  @spec parse(binary()) :: {:ok, job()} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    document = %{stack: [], text: [], job: false, phases: [], messages: [], results: []}

    with {:ok, document} <- XML.parse(xml, __MODULE__, document), do: decode(document)
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, %{stack: stack} = document) do
    role = role(parent(stack), XML.local_name(name), attributes)
    document = %{document | stack: [role | stack]}
    {:ok, start(role, attributes, document)}
  end

  def handle_event(:characters, chars, %{stack: [role | _roles], text: text} = document)
      when role in @text_roles do
    {:ok, %{document | text: [text, chars]}}
  end

  def handle_event(:end_element, _name, %{stack: [role | roles]} = document) do
    {:ok, finish(role, %{document | stack: roles})}
  end

  def handle_event(_event, _data, document), do: {:ok, document}

  #####################
  # Private functions #
  #####################

  # The role of an element follows from its name and the role of its parent,
  # so an element only counts where UWS 1.1 §2.2.1.1 puts it: a phase is the
  # job's only as a child of the job.
  defp parent([role | _roles]), do: role
  defp parent([]), do: nil

  defp role(nil, "job", _attributes), do: :job
  defp role(:job, "phase", _attributes), do: :phase
  defp role(:job, "errorSummary", _attributes), do: :error_summary
  defp role(:error_summary, "message", _attributes), do: :message
  defp role(:job, "results", _attributes), do: :results

  # A job may list other results besides the one TAP names result (TAP 1.1
  # §2.2), such as the diag and rowcount of CADC, so the result is found by
  # its id.
  defp role(:results, "result", attributes) do
    if attribute(attributes, "id") == "result", do: :result, else: :other
  end

  defp role(_parent, _name, _attributes), do: :other

  # Attributes are matched by local name too, since the href of a result is
  # an XLink attribute, usually written xlink:href.
  defp attribute(attributes, name) do
    Enum.find_value(attributes, fn {key, value} -> XML.local_name(key) == name && value end)
  end

  defp start(:job, _attributes, document), do: %{document | job: true}

  defp start(:result, attributes, document) do
    %{document | results: [attribute(attributes, "href") | document.results]}
  end

  defp start(role, _attributes, document) when role in @text_roles,
    do: %{document | text: []}

  defp start(_role, _attributes, document), do: document

  defp finish(:phase, document), do: %{document | phases: [text(document) | document.phases]}

  defp finish(:message, document),
    do: %{document | messages: [text(document) | document.messages]}

  defp finish(_role, document), do: document

  # Gaia writes its messages in CDATA sections and KOA with character
  # references; Saxy hands both over as text.
  defp text(document), do: document.text |> IO.iodata_to_binary() |> String.trim()

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
  # must exist".
  defp job(:completed, _message, result) when result in [nil, ""] do
    {:error, "the job is COMPLETED and its document lists no result"}
  end

  # An empty message or href says nothing.
  defp job(phase, message, result) do
    {:ok, %{phase: phase, error_summary: present(message), result: present(result)}}
  end

  defp present(""), do: nil
  defp present(value), do: value
end
