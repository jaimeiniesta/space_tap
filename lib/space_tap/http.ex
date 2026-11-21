defmodule SpaceTAP.HTTP do
  @moduledoc false

  # What every request to a TAP service shares, the sync query of SpaceTAP
  # and the requests about an async job of SpaceTAP.Job: the parameters of a
  # query, the Req options SpaceTAP sets, how a response becomes an error,
  # and how a result is read.

  alias SpaceTAP.{CSV, Error, Result, VOTable}

  @user_agent "space_tap/#{Mix.Project.config()[:version]}"

  @type result :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  # The parameters of a query, the same for a sync query and for the job of
  # an async one (TAP 1.1 §2.7, §5.1.1), from options SpaceTAP.Options has
  # checked. REQUEST is required by TAP 1.0 (§2.3.1) and ignored by TAP 1.1
  # (§2.7). TAP 1.1 services must accept FORMAT as RESPONSEFORMAT (§2.7.3),
  # and parameter values are case sensitive (DALI 1.1 §3.1). MAXREC goes
  # only when given, and 0 is sent (DALI 1.1 §3.4.4).
  @spec query_form(String.t(), :csv | :votable, non_neg_integer() | nil) :: keyword()
  def query_form(adql, format, maxrec) do
    [REQUEST: "doQuery", LANG: "ADQL", FORMAT: Atom.to_string(format), QUERY: adql] ++
      maxrec(maxrec)
  end

  defp maxrec(nil), do: []
  defp maxrec(maxrec), do: [MAXREC: maxrec]

  # A sync query (TAP 1.1 §2.1): one POST to /sync under the service URL,
  # whose response is the result, read in the format asked for.
  @spec sync(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def sync(service_url, adql, opts) do
    form = query_form(adql, opts[:format], opts[:maxrec])
    url = String.trim_trailing(service_url, "/") <> "/sync"

    opts[:req_options]
    |> run(method: :post, url: url, form: form)
    |> read_result(opts[:format])
  end

  # Runs a request with the caller's :req_options and SpaceTAP's own
  # options, which win.
  @spec run(keyword(), keyword()) :: result()
  def run(req_options, options) do
    {_request, response} = request(req_options, options)
    response
  end

  # GETs `url` as run/2 would, and gives the URL the redirects led to as
  # well, which Req keeps in the request it returns: the base of the
  # document in the response, against which a relative URL it lists
  # resolves (RFC 3986 §5.1.3), and the URL of a job.
  @spec fetch(keyword(), String.t(), keyword()) :: {String.t(), result()}
  def fetch(req_options, url, options \\ []) do
    {request, response} = request(req_options, [method: :get, url: url] ++ options)
    {URI.to_string(request.url), response}
  end

  # The body decides before the status: TAP 1.1 §3.3 lets a service send an
  # error document with 200 as well as 4xx or 5xx. A successful response
  # that isn't an error document is given as read: the body, as read_xml
  # read it when its media type is XML, with the media type and the status.
  @spec classify(result(), (binary() -> term())) ::
          {:ok, term(), String.t() | nil, integer()} | {:error, Error.t()}
  def classify({:error, exception}, _read_xml) do
    error(:transport_error, Exception.message(exception), nil)
  end

  def classify({:ok, %Req.Response{status: status, body: body} = response}, read_xml) do
    media_type = media_type(response)

    case read_body(media_type, body, read_xml) do
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
        {:ok, body, media_type, status}

      body ->
        error(:http_error, http_error_message(body, media_type), status)
    end
  end

  # Reads the result of a query, sync or async, in the format asked for.
  # XML is read as a VOTable whatever the status, since an error document
  # may come with any.
  @spec read_result(result(), :csv | :votable) :: {:ok, Result.t()} | {:error, Error.t()}
  def read_result(response, format) do
    with {:ok, body, media_type, status} <- classify(response, &{:votable, VOTable.parse(&1)}) do
      result(body, format, media_type, status)
    end
  end

  # Reads a VOSI document, /capabilities or /availability, with `read`,
  # which gives what it reads or the reason it can't. The body is read as
  # XML when its media type is XML or when it has none, since KOA sends
  # both with no Content-Type (ADR 0014). A document `read` takes is the
  # answer whatever the status, since the body decides before the status
  # (ADR 0001): a service may send its availability with a 503.
  @spec read_vosi(result(), (binary() -> {:ok, value} | {:error, String.t()})) ::
          {:ok, value} | {:error, Error.t()}
        when value: term()
  def read_vosi({:error, exception}, _read) do
    error(:transport_error, Exception.message(exception), nil)
  end

  def read_vosi({:ok, %Req.Response{status: status, body: body} = response}, read) do
    media_type = media_type(response)
    xml = is_nil(media_type) or xml?(media_type)

    case if(xml, do: read.(body), else: :other) do
      {:ok, value} ->
        {:ok, value}

      {:error, message} when status in 200..299 ->
        error(:decode_error, message, status)

      :other when status in 200..299 ->
        error(:decode_error, "expected an XML document, got #{media_type}", status)

      _other ->
        body = read_body(media_type, body, fn _xml -> :other end)
        error(:http_error, http_error_message(body, media_type), status)
    end
  end

  # Where to read a listed URL, one the service at `from_url` gave in a
  # response, and with which options: the job a 303 points to, the result a
  # job document lists or the availability the capabilities list
  # (docs/adr/0015-listed-urls-are-read-by-one-rule.md). Never over http://
  # after https://: an http:// URL on the host of `from_url` is read with
  # https://, which GAVO and the NASA Exoplanet Archive serve, and one on
  # another host isn't read, which `what`, such as "the job lists its
  # result", explains. Nor is a URL with another scheme, which Req would
  # raise on, or with user information in it, which a recipient treats as
  # an error (RFC 9110 §4.2.4) and Req would turn into Basic auth.
  # Credentials stay with the scheme, host and port of `from_url`, as Req
  # keeps them from a redirect that leaves them (its :redirect_trusted
  # option).
  @spec listed(keyword(), String.t(), String.t(), String.t()) ::
          {:ok, String.t(), keyword()} | {:error, Error.t()}
  def listed(req_options, from_url, url, what) do
    case secure(from_url, url) do
      {:ok, url} -> {:ok, url, credentials(req_options, from_url, url)}
      {:refused, reason, url} -> error(:decode_error, "#{what} at #{reason}: #{url}", nil)
    end
  end

  # The credentials half of the rule for listed URLs: the options for a
  # request to `url`, from those given for `from_url`. SpaceTAP.Job applies
  # it to a job URL `listed/4` has already read, with the options of each
  # call about the job.
  @spec credentials(keyword(), String.t(), String.t()) :: keyword()
  def credentials(req_options, from_url, url) do
    if origin(from_url) == origin(url) do
      req_options
    else
      req_options
      |> Keyword.delete(:auth)
      |> Keyword.replace_lazy(:headers, &without_authorization/1)
    end
  end

  @spec error(Error.type(), String.t(), integer() | nil) :: {:error, Error.t()}
  def error(type, message, status) do
    {:error, %Error{type: type, message: message, status: status}}
  end

  #####################
  # Private functions #
  #####################

  defp request(req_options, options) do
    # classify/2 reads the raw body of every response itself, so Req must
    # not decode it, stream it elsewhere or raise on an error status.
    options =
      [user_agent: @user_agent, decode_body: false, http_errors: :return, into: nil] ++ options

    # Each request is sent once, unless the caller asks Req to retry: Req
    # would retry a GET that fails with a 5xx or a timeout three times,
    # waiting as long as a Retry-After header says
    # (docs/adr/0016-each-request-is-sent-once.md).
    {request, response} =
      req_options
      |> Keyword.put_new(:retry, false)
      |> Keyword.merge(options)
      |> Req.new()
      |> Req.Request.run_request()

    case response do
      %Req.Response{} -> {request, {:ok, response}}
      exception -> {request, {:error, exception}}
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
      {:error, message} -> error(:decode_error, message, status)
    end
  end

  # The only place that tells media types apart.
  defp read_body("text/csv", body, _read_xml), do: {:csv, body}
  defp read_body("text/plain", body, _read_xml), do: {:plain_text, body}

  defp read_body(media_type, body, read_xml) do
    if xml?(media_type), do: read_xml.(body), else: :other
  end

  # The message of an error document is optional (DALI 1.1 §4.4.2).
  defp service_error_message(""), do: "the TAP service reported an error without a message"
  defp service_error_message(message), do: message

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

  # The URL to read, or the reason it isn't read, with the URL to name: one
  # with user information is named without it, so that no password is
  # written in a message.
  defp secure(from_url, url) do
    from = URI.parse(from_url)
    to = URI.parse(url)

    cond do
      to.scheme not in ["http", "https"] ->
        {:refused, "a URL that isn't http:// or https://, which isn't read", url}

      to.userinfo != nil ->
        {:refused, "a URL with user information in it (RFC 9110 §4.2.4), which isn't read",
         URI.to_string(%{to | userinfo: nil})}

      from.scheme != "https" or to.scheme != "http" ->
        {:ok, url}

      host(to) == host(from) and to.port == 80 ->
        {:ok, URI.to_string(%{to | scheme: "https", port: 443})}

      true ->
        {:refused, "an http:// URL, which isn't read after https://", url}
    end
  end

  defp origin(url) do
    uri = URI.parse(url)
    {uri.scheme, host(uri), uri.port}
  end

  # A host is case-insensitive (RFC 3986 §3.2.2).
  defp host(%URI{host: nil}), do: nil
  defp host(%URI{host: host}), do: String.downcase(host)

  defp without_authorization(headers) do
    Enum.reject(headers, fn {name, _value} ->
      name |> to_string() |> String.downcase() == "authorization"
    end)
  end

  # application/xml, text/xml and +xml types such as application/x-votable+xml
  # (RFC 7303 §4.2).
  defp xml?(media_type) do
    is_binary(media_type) and String.ends_with?(media_type, ["/xml", "+xml"])
  end
end
