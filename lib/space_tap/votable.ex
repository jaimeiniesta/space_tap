defmodule SpaceTAP.VOTable do
  @moduledoc false

  # Reads the query status of a VOTable document. DALI 1.1 §4.4 puts it in an
  # INFO element named QUERY_STATUS: the value attribute is OK, ERROR or
  # OVERFLOW, and the element content is the message. Services add other INFOs
  # (Gaia sends HttpErrorCode and Action), so the element is found by name. An
  # overflow document has two, OK before the table and OVERFLOW after it, and
  # the last one counts (DALI §4.4.1).
  #
  # The SAX parser rejects entity declarations, so a document can't expand
  # entities into a huge message, and skips external DTDs, so it never reads a
  # file or URL the document points to. The predefined entities (&amp;, &lt;...)
  # and character references are still decoded.

  @type query_status :: {value :: String.t(), message :: String.t()}

  @spec query_status(binary()) :: {:ok, query_status() | nil} | {:error, String.t()}
  def query_status(xml) when is_binary(xml) do
    options = [
      :disallow_entities,
      :skip_external_dtd,
      event_fun: &event/3,
      event_state: {nil, nil}
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, {last, nil}, rest} -> after_root(rest, last)
      {_tag, _location, reason, _end_tags, _state} -> {:error, "invalid XML: " <> reason(reason)}
    end
  end

  #####################
  # Private functions #
  #####################

  # stream/2 stops at the root's end tag and returns the rest unchecked. XML 1.0
  # §2.1 allows only Misc after the root: whitespace, comments and processing
  # instructions (§2.8). Anything else, such as a second document, is an error
  # rather than something to skip. A comment can't contain "--" (§2.5) and a
  # processing instruction can't contain "?>" (§2.6), so neither match can run
  # past its own end and swallow what follows.
  defp after_root(rest, last) do
    if Regex.match?(~r/\A(?:[ \t\r\n]|<!--(?:[^-]|-[^-])*-->|<\?(?:[^?]|\?(?!>))*\?>)*\z/, rest) do
      {:ok, last}
    else
      {:error, "invalid XML: content after the root element"}
    end
  end

  # The state is {last QUERY_STATUS seen, QUERY_STATUS being read}. Element
  # names are matched without their namespace, which changes with the VOTable
  # version.
  defp event({:startElement, _uri, ~c"INFO", _qname, attributes}, _location, {last, nil}) do
    case attribute(attributes, ~c"name") do
      ~c"QUERY_STATUS" -> {last, {attribute(attributes, ~c"value"), []}}
      _other -> {last, nil}
    end
  end

  defp event({:characters, chars}, _location, {last, {value, chunks}}) do
    {last, {value, [chunks, chars]}}
  end

  defp event({:endElement, _uri, ~c"INFO", _qname}, _location, {_last, {value, chunks}}) do
    message = chunks |> List.to_string() |> String.trim()
    {{to_string(value), message}, nil}
  end

  defp event(_event, _location, state), do: state

  defp attribute(attributes, name) do
    Enum.find_value(attributes, fn
      {_uri, _prefix, ^name, value} -> value
      _attribute -> nil
    end)
  end

  # stream/2 asks for more input when the document ends early. Without a
  # continuation function it reports that instead of the truncation.
  defp reason(~c"Continuation function undefined"), do: "unexpected end of document"
  defp reason(reason) when is_list(reason), do: reason |> List.to_string() |> String.trim()
  defp reason(reason), do: inspect(reason)
end
