defmodule SpaceTAP do
  @moduledoc """
  Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol
  astronomical archives use to expose tabular data.

  `query/3` sends a query written in ADQL to a TAP service and returns its
  result as a `SpaceTAP.Result`, or a `SpaceTAP.Error` when it fails.
  `async_query/3` does the same with a query the service runs as a job, for
  queries that take longer than a sync query may; `SpaceTAP.Job` has each
  step of it.

  SpaceTAP follows [TAP 1.1](https://www.ivoa.net/documents/TAP/20190927/REC-TAP-1.1.html)
  and works with TAP 1.0 services.
  """

  alias SpaceTAP.{Error, HTTP, Job, Result}

  @typedoc "An option for `query/3` or `async_query/3`."
  @type option ::
          {:format, :csv | :votable} | {:maxrec, non_neg_integer()} | {:req_options, keyword()}

  @typedoc "An option for `async_query/3`."
  @type async_option :: option() | {:timeout, timeout()}

  @doc """
  Runs a sync query: sends `adql` to the TAP service at `service_url` and
  returns its result.

  `service_url` is the base URL of the service, such as
  `"https://gea.esac.esa.int/tap-server/tap"` for the Gaia archive. The query
  goes to its `/sync` endpoint (TAP 1.1 §2.4), appended after trimming any
  trailing `/`, so pass the base URL even if you know the endpoint.

  Use the `https://` URL when the service has one. Req follows a 301 or 302
  redirect with a GET that drops the query (RFC 9110 §15.4.2, §15.4.3), so a
  service that redirects `http://` to `https://` gets no query, and the
  request fails.

      SpaceTAP.query(
        "https://gea.esac.esa.int/tap-server/tap",
        "SELECT TOP 3 source_id, ra, dec FROM gaiadr3.gaia_source"
      )
      #=> {:ok, %SpaceTAP.Result{columns: ["source_id", "ra", "dec"], rows: [...]}}

  The result comes as CSV by default, so every value is a string and an
  empty cell is `nil`. With `format: :votable` it comes as VOTable, so each
  value has the type its column declares, and the result describes each
  column and says whether the service truncated it (see `SpaceTAP.Result`):

      SpaceTAP.query(
        "https://gea.esac.esa.int/tap-server/tap",
        "SELECT TOP 3 source_id, ra, dec FROM gaiadr3.gaia_source",
        format: :votable
      )
      #=> {:ok, %SpaceTAP.Result{columns: ["source_id", "ra", "dec"], rows: [...], fields: [...], overflow: false}}

  Errors come as `{:error, %SpaceTAP.Error{}}`, whose `:type` says what went
  wrong.

  ## Options

    * `:format` - the format to ask the service for, `:csv` (the default) or
      `:votable`, sent as `FORMAT` (TAP 1.1 §2.7.3). The format decides the
      value types, so a VOTable sent when CSV was asked for, as MAST sends, is
      a `:decode_error` that says to pass `format: :votable`.
    * `:maxrec` - the maximum number of rows to return, a non-negative
      integer. The service may apply a lower limit of its own, and `0`
      returns the columns with no rows (DALI 1.1 §3.4.4).
    * `:req_options` - a keyword list of options for `Req.new/1`, such as
      `:receive_timeout` to wait longer than Req's default 15 seconds.
      SpaceTAP sets `:method`, `:url`, `:form`, `:user_agent`,
      `:decode_body`, `:http_errors` and `:into` itself, and ignores them
      here. Other options go to Req as given, and some change the request:
      a `user-agent` in `:headers` replaces SpaceTAP's, and `:params` adds
      parameters to the URL.

  An unknown option, or a `:format`, `:maxrec` or `:req_options` that isn't
  what the list above says, raises `ArgumentError`.
  """
  @spec query(String.t(), String.t(), [option()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def query(service_url, adql, opts \\ []) when is_binary(service_url) and is_binary(adql) do
    opts = Keyword.validate!(opts, [:maxrec, format: :csv, req_options: []])
    form = HTTP.query_form(adql, opts[:format], opts[:maxrec])
    url = String.trim_trailing(service_url, "/") <> "/sync"

    {_url, response} =
      opts[:req_options]
      |> HTTP.req_options()
      |> HTTP.run(method: :post, url: url, form: form)

    HTTP.read_result(response, opts[:format])
  end

  @doc """
  Runs an async query: sends `adql` to the TAP service at `service_url` as
  a job, waits for it, reads its result and deletes the job.

  Use it for a query that takes longer than the service lets a sync query
  run. It returns what `query/3` returns, with the same options, and a
  `:timeout`:

      SpaceTAP.async_query(
        "https://dc.g-vo.org/tap",
        "SELECT TOP 5 hipno, ra, dec, vmag FROM hipparcos.main",
        format: :votable,
        timeout: :timer.minutes(30)
      )
      #=> {:ok, %SpaceTAP.Result{columns: ["hipno", "ra", "dec", "vmag"], rows: [...], ...}}

  It goes through the steps in `SpaceTAP.Job`: `SpaceTAP.Job.submit/3`,
  `SpaceTAP.Job.wait/2`, `SpaceTAP.Job.result/2` and
  `SpaceTAP.Job.delete/2`. A job that stops in a phase other than
  `:completed`, such as `:error` or `:aborted`, gives a `:service_error`
  with the service's message.

  The job is deleted whatever happens: once it has stopped, when it can't
  be started, or when the time runs out, which stops it if it is still
  running. When the service won't delete it, the result or error is
  returned all the same, and the job stays on the service until the
  service destroys it, which IRSA never does. So does the job of a process
  that dies while it waits. To keep a job, for example to read its result
  in TOPCAT or to wait longer, use the steps in `SpaceTAP.Job`.

  ## Options

  Those of `query/3`, and:

    * `:timeout` - how long to wait for the job, in milliseconds, or
      `:infinity` (the default), as for `SpaceTAP.Job.wait/2`. When it runs
      out, the job is deleted and the error is a `:timeout`.
  """
  @spec async_query(String.t(), String.t(), [async_option()]) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def async_query(service_url, adql, opts \\ [])
      when is_binary(service_url) and is_binary(adql) do
    opts = Keyword.validate!(opts, [:maxrec, format: :csv, req_options: [], timeout: :infinity])
    {timeout, opts} = Keyword.pop(opts, :timeout)
    timeout = Job.timeout!(timeout)
    job_opts = Keyword.take(opts, [:req_options])

    with {:ok, job} <- Job.submit(service_url, adql, opts) do
      result =
        with {:ok, job} <- Job.wait(job, [timeout: timeout] ++ job_opts) do
          Job.result(job, job_opts)
        end

      # Deleting is cleaning up, so its own error doesn't replace the result.
      _deleted = Job.delete(job, job_opts)
      result
    end
  end
end
