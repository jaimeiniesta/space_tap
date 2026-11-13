defmodule SpaceTAP do
  @moduledoc """
  Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol
  astronomical archives use to expose tabular data.

  `query/3` sends a query written in ADQL to a TAP service and returns its
  result as a `SpaceTAP.Result`, or a `SpaceTAP.Error` when it fails.

  SpaceTAP follows [TAP 1.1](https://www.ivoa.net/documents/TAP/20190927/REC-TAP-1.1.html)
  and works with TAP 1.0 services.
  """

  alias SpaceTAP.{CSV, Error, Result, VOTable}

  @user_agent "space_tap/#{Mix.Project.config()[:version]}"

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

    # REQUEST is required by TAP 1.0 (§2.3.1) and ignored by TAP 1.1 (§2.7).
    # TAP 1.1 services must accept FORMAT as RESPONSEFORMAT (§2.7.3), and
    # parameter values are case sensitive (DALI 1.1 §3.1).
    form =
      [REQUEST: "doQuery", LANG: "ADQL", FORMAT: format(opts[:format]), QUERY: adql] ++
        maxrec(opts[:maxrec])

    # classify/2 reads the raw body of every response itself, so Req must
    # not decode it, stream it elsewhere or raise on an error status.
    tap_options = [
      method: :post,
      url: String.trim_trailing(service_url, "/") <> "/sync",
      form: form,
      user_agent: @user_agent,
      decode_body: false,
      http_errors: :return,
      into: nil
    ]

    opts[:req_options]
    |> req_options()
    |> Keyword.merge(tap_options)
    |> Req.new()
    |> Req.request()
    |> classify(opts[:format])
  end

  #####################
  # Private functions #
  #####################

  defp format(format) when format in [:csv, :votable], do: Atom.to_string(format)

  defp format(format) do
    raise ArgumentError, "expected :format to be :csv or :votable, got: #{inspect(format)}"
  end

  defp maxrec(nil), do: []
  defp maxrec(maxrec) when is_integer(maxrec) and maxrec >= 0, do: [MAXREC: maxrec]

  defp maxrec(maxrec) do
    raise ArgumentError, "expected :maxrec to be a non-negative integer, got: #{inspect(maxrec)}"
  end

  defp req_options(req_options) do
    if Keyword.keyword?(req_options) do
      req_options
    else
      raise ArgumentError,
            "expected :req_options to be a keyword list, got: #{inspect(req_options)}"
    end
  end

  # The body decides before the status: TAP 1.1 §3.3 lets a service send an
  # error document with 200 as well as 4xx or 5xx.
  defp classify({:error, exception}, _format) do
    error(:transport_error, Exception.message(exception), nil)
  end

  defp classify({:ok, %Req.Response{status: status, body: body} = response}, format) do
    media_type = media_type(response)

    case read_body(media_type, body) do
      # DALI 1.1 §4.2 allows a VOTable or a plain-text error document. A
      # VOTable shows that a TAP service wrote it: the query status of its
      # RESOURCE of type results is ERROR (DALI §4.4).
      {:votable, {:query_error, message}} ->
        error(:service_error, service_error_message(message), status)

      # Plain text from a proxy or web server looks the same, so plain text is
      # a service error only with a 400, the status for a bad request, as KOA
      # and CADC send (docs/adr/0004-plain-text-with-400-is-a-service-error.md).
      {:plain_text, text} when status == 400 ->
        error(:service_error, text |> String.trim() |> service_error_message(), status)

      body when status in 200..299 ->
        result(body, format, media_type, status)

      body ->
        error(:http_error, http_error_message(body, media_type), status)
    end
  end

  # A successful response that isn't an error document holds a result in the
  # format asked for, or can't be read.
  defp result({:votable, {:ok, table}}, :votable, _media_type, _status) do
    {:ok, votable_result(table)}
  end

  defp result({:votable, {:error, message}}, :votable, _media_type, status) do
    error(:decode_error, message, status)
  end

  # The format decides the value types, so a VOTable sent for CSV, as MAST
  # sends, isn't read (docs/adr/0006-the-format-option-decides-the-value-types.md).
  defp result({:votable, {:ok, _table}}, :csv, media_type, status) do
    message =
      "expected text/csv, got #{media_type}: the response is a VOTable, pass format: :votable to read it"

    error(:decode_error, message, status)
  end

  # TAP 1.1 §3.2 says CSV comes as text/csv, but the NASA Exoplanet Archive
  # and KOA send it as text/plain, although their /capabilities map csv to
  # text/csv. Only CSV was requested, so text/plain is read as CSV too
  # (docs/adr/0003-csv-sent-as-plain-text-is-read-as-csv.md).
  defp result({type, csv}, :csv, _media_type, status) when type in [:csv, :plain_text] do
    csv_result(csv, status)
  end

  defp result(_body, format, media_type, status) do
    error(
      :decode_error,
      "expected #{expected(format)}, got #{media_type || "no Content-Type"}",
      status
    )
  end

  # The only place that tells media types apart. XML is read as a VOTable
  # whatever the status, since an error document may come with any.
  defp read_body("text/csv", body), do: {:csv, body}
  defp read_body("text/plain", body), do: {:plain_text, body}

  defp read_body(media_type, body) do
    if xml?(media_type), do: {:votable, VOTable.parse(body)}, else: :other
  end

  # Any XML media type can carry a VOTable: KOA and MAST send text/xml, and
  # the NASA Exoplanet Archive application/xml.
  defp expected(:csv), do: "text/csv"
  defp expected(:votable), do: "a VOTable"

  # The message of an error document is optional (DALI 1.1 §4.4.2).
  defp service_error_message(""), do: "the TAP service reported an error without a message"
  defp service_error_message(message), do: message

  defp votable_result(%{fields: fields, rows: rows, overflow: overflow}) do
    columns = Enum.map(fields, & &1.name)
    %Result{columns: columns, rows: rows, fields: fields, overflow: overflow}
  end

  defp csv_result(csv, status) do
    case CSV.parse(csv) do
      {:ok, result} -> {:ok, result}
      {:error, message} -> error(:decode_error, message, status)
    end
  end

  # The text of a plain-text body, such as a proxy's, says more than its
  # media type.
  defp http_error_message({:plain_text, text}, media_type) do
    case String.trim(text) do
      "" -> http_error_message(:other, media_type)
      text -> text
    end
  end

  defp http_error_message(_body, nil), do: "unexpected response with no Content-Type"
  defp http_error_message(_body, media_type), do: "unexpected #{media_type} response"

  defp error(type, message, status) do
    {:error, %Error{type: type, message: message, status: status}}
  end

  # The type and subtype of a media type are case-insensitive, and parameters
  # such as charset follow a semicolon (RFC 9110 §8.3.1). An empty
  # Content-Type gives no media type, as a missing one does.
  defp media_type(response) do
    media_type =
      response
      |> Req.Response.get_header("content-type")
      |> List.first("")
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim()
      |> String.downcase()

    if media_type == "", do: nil, else: media_type
  end

  # application/xml, text/xml and +xml types such as application/x-votable+xml
  # (RFC 7303 §4.2).
  defp xml?(media_type) do
    is_binary(media_type) and String.ends_with?(media_type, ["/xml", "+xml"])
  end
end
