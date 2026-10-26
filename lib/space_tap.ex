defmodule SpaceTAP do
  @moduledoc """
  Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol
  astronomical archives use to expose tabular data.
  """

  alias SpaceTAP.{CSV, Error, Result, VOTable}

  @user_agent "space_tap/#{Mix.Project.config()[:version]}"

  @doc """
  Runs a sync query: sends `adql` to the TAP service at `service_url` and
  returns its result.

  `service_url` is the base URL of the service, such as
  `"https://gea.esac.esa.int/tap-server/tap"` for the Gaia archive. The query
  goes to its `/sync` endpoint (TAP 1.1 §2.4), so pass the base URL even if
  you know the endpoint.

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
    * `:req_options` - options for `Req.new/1`, such as `:receive_timeout`
      to wait longer than Req's default 15 seconds. They can't change the
      TAP request itself: its URL, parameters, body decoding and user agent.
  """
  @spec query(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def query(service_url, adql, opts \\ []) when is_binary(service_url) and is_binary(adql) do
    opts = Keyword.validate!(opts, [:maxrec, req_options: []])

    # REQUEST is required by TAP 1.0 (§2.3.1) and ignored by TAP 1.1 (§2.7).
    # TAP 1.1 services must accept FORMAT as RESPONSEFORMAT (§2.7.3), and
    # parameter values are case sensitive (DALI 1.1 §3.1).
    form = [REQUEST: "doQuery", LANG: "ADQL", FORMAT: "csv", QUERY: adql] ++ maxrec(opts[:maxrec])

    # Req would decode the CSV body itself; CSV.parse/1 reads it instead.
    tap_options = [
      method: :post,
      url: String.trim_trailing(service_url, "/") <> "/sync",
      form: form,
      decode_body: false,
      user_agent: @user_agent
    ]

    opts[:req_options]
    |> Keyword.merge(tap_options)
    |> Req.new()
    |> Req.request()
    |> classify()
  end

  defp maxrec(nil), do: []
  defp maxrec(maxrec) when is_integer(maxrec) and maxrec >= 0, do: [MAXREC: maxrec]

  defp maxrec(maxrec) do
    raise ArgumentError, "expected :maxrec to be a non-negative integer, got: #{inspect(maxrec)}"
  end

  # The body decides before the status: TAP 1.1 §3.3 lets a service send an
  # error document with 200 as well as 4xx or 5xx.
  defp classify({:error, exception}) do
    error(:transport_error, Exception.message(exception), nil)
  end

  defp classify({:ok, %Req.Response{status: status, body: body} = response}) do
    media_type = media_type(response)

    case error_document(media_type, body) do
      {:ok, message} -> error(:service_error, message, status)
      :error when status in 200..299 -> result(media_type, body, status)
      :error -> error(:http_error, http_error_message(media_type, body), status)
    end
  end

  # DALI 1.1 §4.2 allows a plain-text error document too, but only a VOTable
  # shows that a TAP service wrote it: its query status is ERROR (DALI §4.4).
  # Plain text from a proxy or web server looks the same, so it makes an HTTP
  # error (docs/adr/0002-plain-text-is-an-http-error.md).
  defp error_document(media_type, body) do
    if xml?(media_type), do: votable_error(body), else: :error
  end

  defp votable_error(body) do
    case VOTable.query_status(body) do
      {:ok, {"ERROR", message}} -> {:ok, message}
      _other -> :error
    end
  end

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
  # such as charset follow a semicolon (RFC 9110 §8.3.1).
  defp media_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _rest] ->
        content_type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()

      [] ->
        nil
    end
  end

  # application/xml, text/xml and +xml types such as application/x-votable+xml
  # (RFC 7303 §4.2).
  defp xml?(media_type) do
    is_binary(media_type) and String.ends_with?(media_type, ["/xml", "+xml"])
  end
end
