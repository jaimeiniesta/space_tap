defmodule SpaceTAP.Options do
  @moduledoc false

  # The options of the public functions, checked in one place. Each function
  # takes some of the five, and an option it doesn't take, or one that isn't
  # what its docs say, raises ArgumentError: a wrong option is a bug in the
  # caller, not an error of the service. There is no application config.

  @defaults [format: :csv, maxrec: nil, req_options: [], timeout: :infinity, schema: nil]

  @type name :: :format | :maxrec | :req_options | :timeout | :schema

  # The options a function takes, with the default of each one not given.
  @spec validate!(keyword(), [name()]) :: keyword()
  def validate!(opts, names) do
    opts = opts |> keyword!() |> Keyword.validate!(Keyword.take(@defaults, names))
    for {name, value} <- opts, do: {name, check!(name, value)}
  end

  #####################
  # Private functions #
  #####################

  defp keyword!(opts) do
    if Keyword.keyword?(opts),
      do: opts,
      else:
        raise(ArgumentError, "expected the options to be a keyword list, got: #{inspect(opts)}")
  end

  # The format of a result, sent as FORMAT (TAP 1.1 §2.7.3).
  defp check!(:format, format) when format in [:csv, :votable], do: format
  defp check!(:format, format), do: invalid!(":format to be :csv or :votable", format)

  # MAXREC takes a non-negative integer, and 0 is sent (DALI 1.1 §3.4.4).
  defp check!(:maxrec, nil), do: nil
  defp check!(:maxrec, maxrec) when is_integer(maxrec) and maxrec >= 0, do: maxrec
  defp check!(:maxrec, maxrec), do: invalid!(":maxrec to be a non-negative integer", maxrec)

  # Merged into Req.new/1, which takes a keyword list.
  defp check!(:req_options, req_options) do
    if Keyword.keyword?(req_options),
      do: req_options,
      else: invalid!(":req_options to be a keyword list", req_options)
  end

  # Milliseconds, or :infinity, as a receive takes them.
  defp check!(:timeout, timeout)
       when timeout == :infinity or (is_integer(timeout) and timeout >= 0),
       do: timeout

  defp check!(:timeout, timeout),
    do: invalid!(":timeout to be a non-negative integer or :infinity", timeout)

  # The name of a schema in TAP_SCHEMA, or none.
  defp check!(:schema, schema) when is_binary(schema) or is_nil(schema), do: schema
  defp check!(:schema, schema), do: invalid!(":schema to be a string", schema)

  defp invalid!(what, value),
    do: raise(ArgumentError, "expected #{what}, got: #{inspect(value)}")
end
