defmodule SpaceTAP.Error do
  @moduledoc """
  The error a query returns, as `{:error, %SpaceTAP.Error{}}`.

  `:type` says what went wrong:

    * `:service_error` - the TAP service reported that the query failed, for
      example because of invalid ADQL or an unknown table, in a VOTable
      error document whose query status is `ERROR` (DALI 1.1 §4.4), or in
      plain text with HTTP 400 (DALI 1.1 §4.2). `:message` is its message,
      or says that it had none, since the message is optional (DALI 1.1
      §4.4.2). A VOTable error document can come with HTTP 200 as well as
      4xx or 5xx (TAP 1.1 §3.3).
    * `:http_error` - an HTTP error status without an error document from
      the TAP service, such as an HTML page from a proxy. Plain text with
      any status other than 400 is an HTTP error too, because a proxy or
      web server in front of the service may have written it, and
      `:message` is that text.
    * `:transport_error` - no response arrived: the connection failed or
      timed out, or the redirects never ended. `:status` is `nil`.
    * `:decode_error` - a successful response that can't be read as a
      result, such as malformed CSV or a format other than the one
      requested.

  Later versions may add types, so when you match on `:type`, keep a
  clause for the rest.

  `:status` is the HTTP status of the response, and the message starts
  with it:

      iex> error = %SpaceTAP.Error{type: :service_error, message: "Unknown table", status: 400}
      iex> Exception.message(error)
      "(HTTP 400) Unknown table"
  """

  defexception [:type, :message, :status]

  @typedoc "What went wrong. See the module documentation for each type."
  @type type :: :service_error | :http_error | :transport_error | :decode_error

  @typedoc "An error from `SpaceTAP.query/3`, with the HTTP status when a response arrived."
  @type t :: %__MODULE__{
          type: type(),
          message: String.t(),
          status: pos_integer() | nil
        }

  @impl true
  def message(%__MODULE__{message: message, status: nil}), do: message
  def message(%__MODULE__{message: message, status: status}), do: "(HTTP #{status}) #{message}"
end
