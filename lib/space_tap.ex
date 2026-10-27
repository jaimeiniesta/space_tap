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
  @type option :: {:maxrec, non_neg_integer()} | {:req_options, keyword()}

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

  The result comes as CSV, so every value is a string and an empty cell is
  `nil` (see `SpaceTAP.Result`). Errors come as `{:error, %SpaceTAP.Error{}}`,
  whose `:type` says what went wrong.

  ## Options

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

  An unknown option, or a `:maxrec` or `:req_options` that isn't what the
  list above says, raises `ArgumentError`.
  """
  @spec query(String.t(), String.t(), [option()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def query(service_url, adql, opts \\ []) when is_binary(service_url) and is_binary(adql) do
    opts = Keyword.validate!(opts, [:maxrec, req_options: []])

    # REQUEST is required by TAP 1.0 (§2.3.1) and ignored by TAP 1.1 (§2.7).
    # TAP 1.1 services must accept FORMAT as RESPONSEFORMAT (§2.7.3), and
    # parameter values are case sensitive (DALI 1.1 §3.1).
    form = [REQUEST: "doQuery", LANG: "ADQL", FORMAT: "csv", QUERY: adql] ++ maxrec(opts[:maxrec])

    # classify/1 reads the raw body of every response itself, so Req must
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
    |> classify()
  end

  #####################
  # Private functions #
  #####################

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
  defp classify({:error, exception}) do
    error(:transport_error, Exception.message(exception), nil)
  end

  defp classify({:ok, %Req.Response{status: status, body: body} = response}) do
    media_type = media_type(response)

    case service_error(media_type, body) do
      {:ok, message} -> error(:service_error, message, status)
      :error when status in 200..299 -> result(media_type, body, status)
      :error -> error(:http_error, http_error_message(media_type, body), status)
    end
  end

  # DALI 1.1 §4.2 allows a plain-text error document too, but only a VOTable
  # shows that a TAP service wrote it: its query status is ERROR (DALI §4.4).
  # Plain text from a proxy or web server looks the same, so it makes an HTTP
  # error (docs/adr/0002-plain-text-is-an-http-error.md).
  defp service_error(media_type, body) do
    with true <- xml?(media_type),
         {:ok, {"ERROR", message}} <- VOTable.query_status(body) do
      {:ok, service_error_message(message)}
    else
      _other -> :error
    end
  end

  # The message of an error document is optional (DALI 1.1 §4.4.2).
  defp service_error_message(""), do: "the TAP service reported an error without a message"
  defp service_error_message(message), do: message

  defp result("text/csv", body, status) do
    case CSV.parse(body) do
      {:ok, result} -> {:ok, result}
      {:error, message} -> error(:decode_error, message, status)
    end
  end

  defp result(media_type, _body, status) do
    error(:decode_error, "expected text/csv, got #{media_type || "no Content-Type"}", status)
  end

  defp http_error_message(nil, _body), do: "unexpected response with no Content-Type"

  defp http_error_message("text/plain", body) do
    case String.trim(body) do
      "" -> "unexpected text/plain response"
      text -> text
    end
  end

  defp http_error_message(media_type, _body), do: "unexpected #{media_type} response"

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
