defmodule SpaceTAP.Error do
  @moduledoc """
  The error a query returns, as `{:error, %SpaceTAP.Error{}}`.

  `:type` says what went wrong:

    * `:service_error` - the TAP service reported that the query failed, for
      example because of invalid ADQL or an unknown table. It sends an error
      document, a VOTable whose query status is `ERROR` (DALI 1.1 §4.4) or
      plain text with an HTTP error status, and `:message` is its message.
      The HTTP status can be 200 as well as 4xx or 5xx (TAP 1.1 §3.3).
    * `:http_error` - an HTTP error status without an error document, such
      as an HTML page from a proxy.
    * `:transport_error` - no response arrived: the connection failed or
      timed out. `:status` is `nil`.
    * `:decode_error` - a successful response that can't be read as a
      result, such as malformed CSV or a format other than the one
      requested.

  `:status` is the HTTP status of the response, and the message starts
  with it:

      iex> error = %SpaceTAP.Error{type: :service_error, message: "Unknown table", status: 400}
      iex> Exception.message(error)
      "(HTTP 400) Unknown table"
  """

  defexception [:type, :message, :status]

  @type type :: :service_error | :http_error | :transport_error | :decode_error

  @type t :: %__MODULE__{
          type: type(),
          message: String.t(),
          status: pos_integer() | nil
        }

  @impl true
  def message(%__MODULE__{message: message, status: nil}), do: message
  def message(%__MODULE__{message: message, status: status}), do: "(HTTP #{status}) #{message}"
end
