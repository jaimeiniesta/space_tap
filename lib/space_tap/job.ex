defmodule SpaceTAP.Job do
  @moduledoc """
  An async query as the TAP service runs it: a job (TAP 1.1 §2.2).

  The service keeps the job, with its query, its phase and its result,
  until the client deletes it or the service destroys it. The client keeps
  nothing but the job's URL, which is enough to follow the job, read its
  result or delete it, from any process and at any time
  ([UWS 1.1](https://www.ivoa.net/documents/UWS/20161024/REC-UWS-1.1-20161024.html)).

  `submit/3` creates a job and starts it, `wait/2` waits for it to stop,
  `result/2` reads its result, `get/2` reads a job from its URL, and
  `delete/2` deletes it:

      {:ok, job} =
        SpaceTAP.Job.submit(
          "https://dc.g-vo.org/tap",
          "SELECT TOP 5 hipno, ra, dec, vmag FROM hipparcos.main",
          format: :votable
        )
      #=> {:ok, %SpaceTAP.Job{url: "https://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl", phase: :queued, format: :votable, ...}}

      {:ok, job} = SpaceTAP.Job.wait(job)
      #=> {:ok, %SpaceTAP.Job{phase: :completed, result_url: "http://dc.g-vo.org/__system__/tap/run/async/bjk2rbdl/results/result", ...}}

      SpaceTAP.Job.result(job)
      #=> {:ok, %SpaceTAP.Result{columns: ["hipno", "ra", "dec", "vmag"], rows: [...], ...}}

      SpaceTAP.Job.get(job.url, format: :votable)
      #=> {:ok, %SpaceTAP.Job{phase: :completed, ...}}

      SpaceTAP.Job.delete(job)
      #=> :ok

  Errors come as `{:error, %SpaceTAP.Error{}}`, as from `SpaceTAP.query/3`.
  """

  alias SpaceTAP.{Error, HTTP, Result, UWS, VOTable}

  @enforce_keys [:url, :phase, :format]
  defstruct [:url, :phase, :format, :error_summary, :result_url]

  # The phases the service moves a job on from (UWS 1.1 §2.1.3): a queued or
  # executing job runs, a suspended one is resumed, and an unknown one may
  # become known.
  @moving [:queued, :executing, :suspended, :unknown]

  # The longest a request asks the service to block, in seconds, well under
  # the 120 after which something in front of GAVO cuts the connection
  # without a response. A service that doesn't block is asked again after a
  # pause, from 1 to 30 seconds, 1.5 times longer each time.
  @wait 30
  @first_pause 1_000
  @max_pause 30_000

  # Req's default.
  @receive_timeout 15_000

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

  @typedoc "An option for `submit/3`, `get/2`, `wait/2` or `delete/2`."
  @type option ::
          {:format, :csv | :votable}
          | {:maxrec, non_neg_integer()}
          | {:timeout, timeout()}
          | {:req_options, keyword()}

  @doc """
  Creates a job that runs `adql` on the TAP service at `service_url`, and
  starts it.

  `service_url` is the base URL of the service, as for `SpaceTAP.query/3`,
  and the `https://` one when the service has it: the service answers the
  query with a 303 to the new job, and any other redirect, such as one from
  `http://` to `https://`, is an `:http_error`. The query goes to its
  `/async` endpoint (TAP 1.1 §2.2), with the same parameters as a sync
  query. The service answers with the URL of the job
  (UWS 1.1 §2.2.3.1), and if the job is still `:pending`, which is how most
  services leave a new job, `submit/3` starts it.

  Returns the job as the service then describes it: usually `:queued` or
  `:executing`, or already ended when the service runs a small query
  straight away. When the service creates the job but it can't be read or
  started, `submit/3` deletes it and returns the error, since the error
  doesn't give the job's URL.

  The job is never read over `http://` for a service at an `https://` URL.
  When the service answers with an `http://` URL on its own host, as the
  NASA Exoplanet Archive does, the job is read with `https://`, and one on
  another host isn't read, nor deleted: it is a `:decode_error` that names
  it. On another host, scheme or port, the `authorization` header and Req's
  `:auth` option aren't sent, as Req does when a redirect leads to another
  host.

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

    # The service answers 303 with the URL of the job (UWS 1.1 §2.2.3.1),
    # which isn't followed, so that SpaceTAP knows the job exists even if
    # what comes next fails, and is read as any URL a service lists: with
    # https:// when the service gives http:// on its own host, as the NASA
    # Exoplanet Archive does, and without credentials on another host.
    {_url, response} =
      HTTP.run(req_options, method: :post, url: url, form: form, redirect: false)

    case response do
      {:ok, %Req.Response{status: 303} = response} ->
        with {:ok, listed_url} <- job_location(response, url),
             {:ok, job_url, req_options} <-
               HTTP.listed(req_options, url, listed_url, "the service lists the new job") do
          run(job_url, opts[:format], req_options)
        end

      # Only a 303 points to a job. Another redirect is the web server's,
      # such as one from http:// to https://, whose Location is the list of
      # jobs: reading it as a job would fail, and deleting it would be a
      # request to that list, where a POST creates a job.
      {:ok, %Req.Response{status: status} = response} when status in 300..399 ->
        location = response |> Req.Response.get_header("location") |> List.first()

        message =
          "expected a 303 to the new job (UWS 1.1 §2.2.3.1), got a redirect to #{location}"

        HTTP.error(:http_error, message, status)

      response ->
        HTTP.classify(response, &read_job/1, fn _body, media_type, status ->
          message = "expected a redirect to the new job, got #{media_type || "no Content-Type"}"
          HTTP.error(:decode_error, message, status)
        end)
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
  Waits for `job` to stop, and returns it as the service then describes it.

  The wait ends when the job reaches a phase it won't leave without the
  client (UWS 1.1 §2.1.3): `:completed`, `:error`, `:aborted` or
  `:archived`, or `:pending` or `:held`, which wait for the client to start
  the job. While it is `:queued`, `:executing`, `:suspended` or `:unknown`,
  the service moves it on, and `wait/2` keeps asking.

  Each request asks the service to answer when the phase changes, or after
  30 seconds (the `WAIT` parameter of UWS 1.1 §2.2.1.2). A service that
  answers straight away instead, as the Gaia archive and IRSA do, is asked
  again after a pause that starts at a second and grows to 30 seconds.

      {:ok, job} = SpaceTAP.Job.wait(job, timeout: :timer.minutes(10))
      #=> {:ok, %SpaceTAP.Job{phase: :completed, ...}}

  ## Options

    * `:timeout` - how long to wait, in milliseconds, or `:infinity` (the
      default). A service stops a job that runs longer than its limit, 60
      seconds for anonymous users of the Gaia archive, but not one that
      waits in its queue, and some limits are long: IRSA's is 3 days. So
      without a `:timeout` the wait lasts as long as the job, queue
      included. When the time runs out, `wait/2` returns a `:timeout` error
      and leaves the job on the service. The time is checked between
      requests, so a request under way may end a few seconds after it.
    * `:req_options` - a keyword list of options for `Req.new/1`. A request
      that asks the service to wait gets a `:receive_timeout` long enough for
      it, whatever this one says.

  An unknown option, or a `:timeout` that isn't what the list says, raises
  `ArgumentError`.
  """
  @spec wait(t(), [option()]) :: {:ok, t()} | {:error, Error.t()}
  def wait(%__MODULE__{} = job, opts \\ []) do
    opts = Keyword.validate!(opts, timeout: :infinity, req_options: [])

    state = %{
      req_options: HTTP.req_options(opts[:req_options]),
      timeout: opts[:timeout],
      deadline: deadline(opts[:timeout]),
      pause: @first_pause
    }

    poll(job, state)
  end

  @doc """
  Reads the result of `job`, which must have stopped, as `SpaceTAP.query/3`
  reads the result of a sync query, in the format the job was submitted
  with.

  A `:completed` job's result comes from its `:result_url`. A job that
  stopped in another phase has none, and gives a `:service_error` that
  names the phase and adds the service's message, if any: an `:error` job
  failed, and an `:aborted` one was stopped, by the client or by the
  service, as the Gaia archive stops a job of an anonymous user after 60
  seconds.

  The result never comes over `http://` for a job at an `https://` URL. When
  the service lists an `http://` URL on the job's host, as the NASA Exoplanet
  Archive does, the result is read with `https://`, and from another host it
  isn't read. On another host, such as CADC's `ws-cadc.canfar.net`, the
  `authorization` header and Req's `:auth` option aren't sent, as Req does
  when a redirect leads to another host.

  Raises `ArgumentError` for a job that hasn't stopped: wait for it with
  `wait/2` first.

  ## Options

    * `:req_options` - a keyword list of options for `Req.new/1`.
  """
  @spec result(t(), [option()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def result(%__MODULE__{} = job, opts \\ []) do
    opts = Keyword.validate!(opts, req_options: [])
    read_result(job, HTTP.req_options(opts[:req_options]))
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

        accepted(response)

      {_url, response} ->
        accepted(response)
    end
  end

  # Raises for a :timeout wait/2 can't use, which SpaceTAP.async_query/3
  # checks before it creates a job.
  @doc false
  @spec timeout!(term()) :: timeout()
  def timeout!(timeout) when timeout == :infinity or (is_integer(timeout) and timeout >= 0),
    do: timeout

  def timeout!(timeout) do
    raise ArgumentError,
          "expected :timeout to be a non-negative integer or :infinity, got: #{inspect(timeout)}"
  end

  #####################
  # Private functions #
  #####################

  # The job the 303 points to, resolved against the list of jobs the query
  # went to. A Location that is the list itself, as an empty one resolves
  # to, points to no job: reading it would fail, and deleting it would be a
  # request to the list, where a POST creates a job.
  defp job_location(response, list_url) do
    case Req.Response.get_header(response, "location") do
      [] ->
        HTTP.error(:http_error, "no Location for the new job", 303)

      [location | _locations] ->
        job_url = list_url |> URI.merge(location) |> URI.to_string()

        if String.trim_trailing(job_url, "/") == list_url do
          message =
            "expected a 303 to the new job (UWS 1.1 §2.2.3.1), got one to the list of jobs: " <>
              job_url

          HTTP.error(:http_error, message, 303)
        else
          {:ok, job_url}
        end
    end
  end

  # Reads the new job, where the redirects end, which is its URL. A job
  # SpaceTAP can't read or start is deleted, since the error doesn't give
  # its URL, and nothing else could delete it before the service destroys
  # it, which IRSA never does.
  defp run(job_url, format, req_options) do
    {url, response} = HTTP.run(req_options, method: :get, url: job_url)

    result =
      with {:ok, job} <- HTTP.classify(response, &read_job/1, &job(&1, url, format, &2, &3)) do
        start(job, req_options)
      end

    case result do
      {:ok, job} ->
        {:ok, job}

      {:error, _error} ->
        job = %__MODULE__{url: url, phase: :unknown, format: format}
        _deleted = delete(job, req_options: req_options)
        result
    end
  end

  # A service may start a job from the request that creates it, but GAVO,
  # ESO and CADC don't, so SpaceTAP starts it with a request of its own, and
  # only while it is PENDING, the one phase a client may change it in (DALI
  # 1.1 §2.1). UWS 1.1 §2.2.3.5 answers it with a 303 to the job, but the
  # Gaia archive's points to <job>/phase, so the 303 isn't followed and the
  # job is read at its own URL.
  defp start(%__MODULE__{phase: :pending, url: url} = job, req_options) do
    phase_url = url |> URI.parse() |> URI.append_path("/phase") |> URI.to_string()

    {_url, response} =
      HTTP.run(req_options, method: :post, url: phase_url, form: [PHASE: "RUN"], redirect: false)

    with :ok <- accepted(response) do
      refresh(job, req_options, method: :get, url: url)
    end
  end

  defp start(job, _req_options), do: {:ok, job}

  defp deadline(timeout) do
    case timeout!(timeout) do
      :infinity -> :infinity
      timeout -> now() + timeout
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  # The milliseconds left, or :infinity.
  defp remaining(:infinity), do: :infinity
  defp remaining(deadline), do: max(deadline - now(), 0)

  # A job that has stopped is read once, without WAIT: GAVO blocks a PENDING
  # job for the whole WAIT, although only the client can start it. One that
  # another client has started meanwhile is waited for.
  defp poll(%{phase: phase} = job, state) when phase not in @moving do
    with {:ok, next} <- read(job, state.req_options, nil) do
      if next.phase in @moving, do: poll(next, state), else: {:ok, next}
    end
  end

  # One turn for a job the service moves on: a :timeout once the time has
  # run out, or a request with WAIT, the seconds left at most.
  defp poll(job, state) do
    case remaining(state.deadline) do
      0 ->
        HTTP.error(:timeout, "the job is still #{name(job.phase)} after #{state.timeout} ms", nil)

      remaining ->
        ask(job, state, wait_seconds(remaining))
    end
  end

  defp wait_seconds(:infinity), do: @wait
  defp wait_seconds(milliseconds), do: min(@wait, div(milliseconds, 1000))

  # A service that answers before the WAIT is over, and not because the
  # phase changed, ignored it, and is asked again after a pause, 1.5 times
  # longer each time and never longer than the time left; so is one asked
  # without WAIT, under a second from the deadline. A change of phase is
  # asked about at once.
  defp ask(job, state, wait) do
    started = now()

    with {:ok, next} <- read(job, state.req_options, wait) do
      cond do
        next.phase not in @moving ->
          {:ok, next}

        next.phase == job.phase and (wait == 0 or now() - started < wait * 1000) ->
          Process.sleep(pause(state))
          poll(next, %{state | pause: min(round(state.pause * 1.5), @max_pause)})

        true ->
          poll(next, %{state | pause: @first_pause})
      end
    end
  end

  defp pause(%{deadline: :infinity, pause: pause}), do: pause
  defp pause(%{deadline: deadline, pause: pause}), do: min(pause, remaining(deadline))

  defp read_result(%__MODULE__{phase: phase}, _req_options) when phase in @moving do
    raise ArgumentError,
          "the job is #{name(phase)}: wait for it to stop with SpaceTAP.Job.wait/2 " <>
            "before reading its result"
  end

  defp read_result(%__MODULE__{phase: :completed, result_url: nil}, _req_options) do
    HTTP.error(:decode_error, "the job is COMPLETED and lists no result", nil)
  end

  # The NASA Exoplanet Archive lists http:// URLs on its own host, which it
  # redirects to https://, and GAVO listed them until November 2026.
  defp read_result(%__MODULE__{phase: :completed} = job, req_options) do
    with {:ok, url, req_options} <-
           HTTP.listed(req_options, job.url, job.result_url, "the job lists its result") do
      {_url, response} = HTTP.run(req_options, method: :get, url: url)
      HTTP.read_result(response, job.format)
    end
  end

  # A job that stopped in another phase has no result (UWS 1.1 §2.1.3).
  defp read_result(%__MODULE__{phase: phase, error_summary: summary}, _req_options) do
    message = "the job is #{name(phase)}" <> if(summary, do: ": " <> summary, else: "")
    HTTP.error(:service_error, message, nil)
  end

  defp name(phase), do: phase |> Atom.to_string() |> String.upcase()

  # Without WAIT for a job that has stopped, or with less than a second
  # left, since WAIT takes whole seconds (UWS 1.1 §2.2.1.2). The job keeps
  # its URL: the request went to one with WAIT in it. Asked to block, GAVO
  # answers 5 to 7 seconds after the WAIT is over.
  defp read(job, req_options, wait) when wait in [nil, 0] do
    refresh(job, req_options, method: :get, url: job.url)
  end

  defp read(job, req_options, wait) do
    receive_timeout =
      max(Keyword.get(req_options, :receive_timeout, @receive_timeout), (wait + 30) * 1000)

    refresh(job, req_options,
      method: :get,
      url: job.url,
      params: [WAIT: wait],
      receive_timeout: receive_timeout
    )
  end

  defp refresh(job, req_options, options) do
    with {:ok, next} <- request(req_options, job.format, options) do
      {:ok, %{next | url: job.url}}
    end
  end

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

  # A request that changes a job is answered with a 303 (UWS 1.1 §2.2.3),
  # or a 2xx that isn't an error document.
  defp accepted({:ok, %Req.Response{status: status}}) when status in 300..399, do: :ok

  defp accepted(response) do
    HTTP.classify(response, &{:votable, VOTable.parse(&1)}, fn _body, _media_type, _status ->
      :ok
    end)
  end
end
