defmodule SpaceTAP.Job do
  @moduledoc """
  An async query as the TAP service runs it: a job (TAP 1.1 §2.2).

  The service keeps the job, with its query, its phase and its result,
  until the client deletes it or the service destroys it. The client keeps
  nothing but the job's URL, which is enough to follow the job, read its
  result or delete it, from any process and at any time
  ([UWS 1.1](https://www.ivoa.net/documents/UWS/20161024/REC-UWS-1.1-20161024.html)).

  `submit/3` creates a job and starts it, `get/2` reads a job from its URL,
  and `delete/2` deletes it:

      {:ok, job} =
        SpaceTAP.Job.submit(
          "https://dc.g-vo.org/tap",
          "SELECT TOP 5 hipno, ra, dec, vmag FROM hipparcos.main",
          format: :votable
        )
      #=> {:ok, %SpaceTAP.Job{url: "https://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl", phase: :queued, format: :votable, ...}}

      SpaceTAP.Job.get(job.url, format: :votable)
      #=> {:ok, %SpaceTAP.Job{phase: :completed, result_url: "http://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl/results/result", ...}}

      SpaceTAP.Job.delete(job)
      #=> :ok

  Errors come as `{:error, %SpaceTAP.Error{}}`, as from `SpaceTAP.query/3`.
  """

  alias SpaceTAP.{Error, HTTP, UWS, VOTable}

  @enforce_keys [:url, :phase, :format]
  defstruct [:url, :phase, :format, :error_summary, :result_url]

  @typedoc """
  The state of a job, one of the ten phases of UWS 1.1 §2.1.3.

  A job starts as `:pending`, waits to run as `:queued` and runs as
  `:executing`. It ends as `:completed` when its result is ready, as
  `:error` when it failed, or as `:aborted` when the client or the service
  stopped it. A `:held` job waits for the client to start it again, a
  `:suspended` one for the service to resume it, and an `:archived` one has
  lost its result. `:unknown` is a phase the service doesn't know yet.
  """
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

  @typedoc """
  A job, as its job document described it when it was last read:

    * `:url` - the URL of the job, where the service's redirects led.
    * `:phase` - its phase.
    * `:format` - the format its result was asked for in, `:csv` or
      `:votable`, which decides how the result is read.
    * `:error_summary` - the message the service gives about why the job
      failed, or `nil`.
    * `:result_url` - the URL of its result, as the service lists it, or
      `nil` when it lists none.
  """
  @type t :: %__MODULE__{
          url: String.t(),
          phase: phase(),
          format: :csv | :votable,
          error_summary: String.t() | nil,
          result_url: String.t() | nil
        }

  @typedoc "An option for `submit/3`, `get/2` or `delete/2`."
  @type option ::
          {:format, :csv | :votable} | {:maxrec, non_neg_integer()} | {:req_options, keyword()}

  @doc """
  Creates a job that runs `adql` on the TAP service at `service_url`, and
  starts it.

  `service_url` is the base URL of the service, as for `SpaceTAP.query/3`.
  The query goes to its `/async` endpoint (TAP 1.1 §2.2), with the same
  parameters as a sync query. The service answers with the URL of the job
  (UWS 1.1 §2.2.3.1), and if the job is still `:pending`, which is how most
  services leave a new job, `submit/3` starts it.

  Returns the job as the service then describes it: usually `:queued` or
  `:executing`, or already ended when the service runs a small query
  straight away.

  ## Options

  The same as for `SpaceTAP.query/3`:

    * `:format` - the format to ask for the result in, `:csv` (the default)
      or `:votable`.
    * `:maxrec` - the maximum number of rows of the result.
    * `:req_options` - a keyword list of options for `Req.new/1`.

  An unknown option, or one that isn't what the list says, raises
  `ArgumentError`.
  """
  @spec submit(String.t(), String.t(), [option()]) :: {:ok, t()} | {:error, Error.t()}
  def submit(service_url, adql, opts \\ []) when is_binary(service_url) and is_binary(adql) do
    opts = Keyword.validate!(opts, [:maxrec, format: :csv, req_options: []])
    form = HTTP.query_form(adql, opts[:format], opts[:maxrec])
    req_options = HTTP.req_options(opts[:req_options])
    url = String.trim_trailing(service_url, "/") <> "/async"

    # The service answers 303 with the URL of the job, and Req reads the job
    # there with a GET. Where the redirects end is the URL of the job: the
    # NASA Exoplanet Archive gives an http:// URL, which it redirects to
    # https://.
    with {:ok, job} <- request(req_options, opts[:format], method: :post, url: url, form: form) do
      start(job, req_options)
    end
  end

  @doc """
  Reads the job at `job_url`.

  Use it to follow a job from another process, or later on, with the URL
  of a job `submit/3` returned.

  ## Options

    * `:format` - the format the job's result was asked for in, `:csv` (the
      default) or `:votable`. The job document doesn't say it the same way
      in every service, so pass the one given to `submit/3`.
    * `:req_options` - a keyword list of options for `Req.new/1`.
  """
  @spec get(String.t(), [option()]) :: {:ok, t()} | {:error, Error.t()}
  def get(job_url, opts \\ []) when is_binary(job_url) do
    opts = Keyword.validate!(opts, format: :csv, req_options: [])

    # Nothing is sent with the format, but one SpaceTAP can't read raises
    # here, as it does in submit/3.
    _format = HTTP.format(opts[:format])

    request(HTTP.req_options(opts[:req_options]), opts[:format], method: :get, url: job_url)
  end

  @doc """
  Deletes `job` from the TAP service, which stops it if it is still running
  (UWS 1.1 §2.2.3.2).

  Returns `:ok`, or the error the service gave, such as a 404 for a job it
  has already destroyed. Some services answer that the job is deleted and
  keep it until its destruction time: the NASA Exoplanet Archive, KOA and
  IRSA do.

  ## Options

    * `:req_options` - a keyword list of options for `Req.new/1`.
  """
  @spec delete(t(), [option()]) :: :ok | {:error, Error.t()}
  def delete(%__MODULE__{url: url}, opts \\ []) do
    opts = Keyword.validate!(opts, req_options: [])
    req_options = HTTP.req_options(opts[:req_options])

    # UWS 1.1 §2.2.3.2 deletes a job with DELETE, or with a POST of
    # ACTION=DELETE, which is all NED (403), KOA (500) and the NASA
    # Exoplanet Archive (502) accept. Both answer 303 to the list of jobs,
    # which isn't followed: GAVO's lists hundreds.
    case HTTP.run(req_options, method: :delete, url: url, redirect: false) do
      {_url, {:ok, %Req.Response{status: status}}} when status >= 400 ->
        {_url, response} =
          HTTP.run(req_options,
            method: :post,
            url: url,
            form: [ACTION: "DELETE"],
            redirect: false
          )

        deleted(response)

      {_url, response} ->
        deleted(response)
    end
  end

  #####################
  # Private functions #
  #####################

  # A service may start a job from the request that creates it, but GAVO,
  # ESO and CADC don't, so SpaceTAP starts it with a request of its own, and
  # only while it is PENDING, the one phase a client may change it in (DALI
  # 1.1 §2.1). The service answers 303 to the job (UWS 1.1 §2.2.3.5).
  defp start(%__MODULE__{phase: :pending, url: url, format: format}, req_options) do
    phase_url = url |> URI.parse() |> URI.append_path("/phase") |> URI.to_string()
    request(req_options, format, method: :post, url: phase_url, form: [PHASE: "RUN"])
  end

  defp start(job, _req_options), do: {:ok, job}

  defp request(req_options, format, options) do
    {url, response} = HTTP.run(req_options, options)
    HTTP.classify(response, &read_job/1, &job(&1, url, format, &2, &3))
  end

  # An XML body is a job document, or an error document instead of one.
  defp read_job(body) do
    case UWS.parse(body) do
      {:ok, document} ->
        {:job, document}

      {:error, message} ->
        case VOTable.parse(body) do
          {:query_error, _message} = error -> {:votable, error}
          _other -> {:not_job, message}
        end
    end
  end

  defp job({:job, document}, url, format, _media_type, _status) do
    {:ok,
     %__MODULE__{
       url: url,
       phase: document.phase,
       format: format,
       error_summary: document.error_summary,
       result_url: document.result && url |> URI.merge(document.result) |> URI.to_string()
     }}
  end

  defp job({:not_job, message}, _url, _format, _media_type, status) do
    HTTP.error(:decode_error, message, status)
  end

  defp job(_body, _url, _format, media_type, status) do
    message = "expected a UWS job document, got #{media_type || "no Content-Type"}"
    HTTP.error(:decode_error, message, status)
  end

  # The 303 to the list of jobs, or a 2xx that isn't an error document.
  defp deleted({:ok, %Req.Response{status: status}}) when status in 300..399, do: :ok

  defp deleted(response) do
    HTTP.classify(response, &{:votable, VOTable.parse(&1)}, fn _body, _media_type, _status ->
      :ok
    end)
  end
end
