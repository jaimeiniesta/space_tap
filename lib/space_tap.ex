defmodule SpaceTAP do
  @moduledoc """
  Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol
  astronomical archives use to expose tabular data.

  `query/3` sends a query written in ADQL to a TAP service and returns its
  result as a `SpaceTAP.Result`, or a `SpaceTAP.Error` when it fails.

  SpaceTAP follows [TAP 1.1](https://www.ivoa.net/documents/TAP/20190927/REC-TAP-1.1.html)
  and works with TAP 1.0 services.
  """

  alias SpaceTAP.{CSV, Error, HTTP, Result, VOTable}

  @typedoc "An option for `query/3`."
  @type option ::
          {:format, :csv | :votable} | {:maxrec, non_neg_integer()} | {:req_options, keyword()}

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

    # XML is read as a VOTable whatever the status, since an error document
    # may come with any.
    HTTP.classify(response, &{:votable, VOTable.parse(&1)}, &result(&1, opts[:format], &2, &3))
  end

  #####################
  # Private functions #
  #####################

  # A successful response that isn't an error document holds a result in the
  # format asked for, or can't be read.
  defp result({:votable, {:ok, table}}, :votable, _media_type, _status) do
    {:ok, votable_result(table)}
  end

  defp result({:votable, {:error, message}}, :votable, _media_type, status) do
    HTTP.error(:decode_error, message, status)
  end

  # The format decides the value types, so a VOTable sent for CSV, as MAST
  # sends, isn't read (docs/adr/0006-the-format-option-decides-the-value-types.md).
  defp result({:votable, {:ok, _table}}, :csv, media_type, status) do
    message =
      "expected text/csv, got #{media_type}: the response is a VOTable, pass format: :votable to read it"

    HTTP.error(:decode_error, message, status)
  end

  # TAP 1.1 §3.2 says CSV comes as text/csv, but the NASA Exoplanet Archive
  # and KOA send it as text/plain, although their /capabilities map csv to
  # text/csv. Only CSV was requested, so text/plain is read as CSV too
  # (docs/adr/0003-csv-sent-as-plain-text-is-read-as-csv.md).
  defp result({type, csv}, :csv, _media_type, status) when type in [:csv, :plain_text] do
    csv_result(csv, status)
  end

  defp result(_body, format, media_type, status) do
    HTTP.error(
      :decode_error,
      "expected #{expected(format)}, got #{media_type || "no Content-Type"}",
      status
    )
  end

  # Any XML media type can carry a VOTable: KOA and MAST send text/xml, and
  # the NASA Exoplanet Archive application/xml.
  defp expected(:csv), do: "text/csv"
  defp expected(:votable), do: "a VOTable"

  defp votable_result(%{fields: fields, rows: rows, overflow: overflow}) do
    columns = Enum.map(fields, & &1.name)
    %Result{columns: columns, rows: rows, fields: fields, overflow: overflow}
  end

  defp csv_result(csv, status) do
    case CSV.parse(csv) do
      {:ok, result} -> {:ok, result}
      {:error, message} -> HTTP.error(:decode_error, message, status)
    end
  end
end
