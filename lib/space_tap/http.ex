defmodule SpaceTAP.HTTP do
  @moduledoc false

  # What every request to a TAP service shares, the sync query of SpaceTAP
  # and the requests about an async job of SpaceTAP.Job: the parameters of a
  # query, the Req options SpaceTAP sets, and how a response becomes an
  # error.

  alias SpaceTAP.Error

  @user_agent "space_tap/#{Mix.Project.config()[:version]}"

  @type result :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  # The parameters of a query, the same for a sync query and for the job of
  # an async one (TAP 1.1 §2.7, §5.1.1). REQUEST is required by TAP 1.0
  # (§2.3.1) and ignored by TAP 1.1 (§2.7). TAP 1.1 services must accept
  # FORMAT as RESPONSEFORMAT (§2.7.3), and parameter values are case
  # sensitive (DALI 1.1 §3.1).
  @spec query_form(String.t(), term(), term()) :: keyword()
  def query_form(adql, format, maxrec) do
    [REQUEST: "doQuery", LANG: "ADQL", FORMAT: format(format), QUERY: adql] ++ maxrec(maxrec)
  end

  @spec format(term()) :: String.t()
  def format(format) when format in [:csv, :votable], do: Atom.to_string(format)

  def format(format) do
    raise ArgumentError, "expected :format to be :csv or :votable, got: #{inspect(format)}"
  end

  defp maxrec(nil), do: []
  defp maxrec(maxrec) when is_integer(maxrec) and maxrec >= 0, do: [MAXREC: maxrec]

  defp maxrec(maxrec) do
    raise ArgumentError, "expected :maxrec to be a non-negative integer, got: #{inspect(maxrec)}"
  end

  @spec req_options(term()) :: keyword()
  def req_options(req_options) do
    if Keyword.keyword?(req_options) do
      req_options
    else
      raise ArgumentError,
            "expected :req_options to be a keyword list, got: #{inspect(req_options)}"
    end
  end

  # Runs a request with the caller's :req_options and SpaceTAP's own
  # options, which win. Gives the URL the redirects led to as well, which
  # Req keeps in the request it returns.
  @spec run(keyword(), keyword()) :: {String.t(), result()}
  def run(req_options, options) do
    # classify/3 reads the raw body of every response itself, so Req must
    # not decode it, stream it elsewhere or raise on an error status.
    options =
      [user_agent: @user_agent, decode_body: false, http_errors: :return, into: nil] ++ options

    {request, response} =
      req_options
      |> Keyword.merge(options)
      |> Req.new()
      |> Req.Request.run_request()

    case response do
      %Req.Response{} -> {URI.to_string(request.url), {:ok, response}}
      exception -> {URI.to_string(request.url), {:error, exception}}
    end
  end

  # The body decides before the status: TAP 1.1 §3.3 lets a service send an
  # error document with 200 as well as 4xx or 5xx. read_xml reads an XML
  # body, and success gets what it read from a successful response that
  # isn't an error document, with its media type and status.
  @spec classify(result(), (binary() -> term()), (term(), String.t() | nil, integer() -> result)) ::
          result | {:error, Error.t()}
        when result: term()
  def classify({:error, exception}, _read_xml, _success) do
    error(:transport_error, Exception.message(exception), nil)
  end

  def classify({:ok, %Req.Response{status: status, body: body} = response}, read_xml, success) do
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
        success.(body, media_type, status)

      body ->
        error(:http_error, http_error_message(body, media_type), status)
    end
  end

  @spec error(Error.type(), String.t(), integer() | nil) :: {:error, Error.t()}
  def error(type, message, status) do
    {:error, %Error{type: type, message: message, status: status}}
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

  # application/xml, text/xml and +xml types such as application/x-votable+xml
  # (RFC 7303 §4.2).
  defp xml?(media_type) do
    is_binary(media_type) and String.ends_with?(media_type, ["/xml", "+xml"])
  end
end
