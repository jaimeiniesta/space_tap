defmodule SpaceTAP.XML do
  @moduledoc false

  # What the readers of XML documents share, SpaceTAP.VOTable for results
  # and error documents and SpaceTAP.UWS for job documents: parsing with
  # Saxy (ADR 0008) without expanding entities, and matching names without
  # their namespace prefix, which changes from one service to another.

  @spec parse(binary(), module(), state) :: {:ok, state} | {:error, String.t()} when state: term()
  def parse(xml, handler, state) do
    case Saxy.parse_string(xml, handler, state, expand_entity: {__MODULE__, :entity, []}) do
      {:ok, state} -> {:ok, state}
      {:error, exception} -> {:error, "invalid XML: " <> Exception.message(exception)}
    end
  catch
    {:entity, name} -> {:error, "invalid XML: &#{name}; is not a predefined entity"}
  end

  # Saxy decodes the five predefined entities (&amp;, &lt;...) and character
  # references itself, skips the DTD, and calls this function for any other
  # entity reference. A non-validating parser has to expand the entities the
  # DTD declares (XML 1.0 §5.1), and one the DTD doesn't declare is an error
  # (§4.1), so keeping the reference as text would turn "&author;" into the
  # value of a cell. SpaceTAP expands none, so a document can't make a small
  # response grow into a huge one or read a file the DTD points to.
  @doc false
  @spec entity(String.t()) :: no_return()
  def entity(name), do: throw({:entity, name})

  # What follows the first colon, found without compiling a pattern for each
  # element, as :binary.split/2 would.
  @spec local_name(String.t()) :: String.t()
  def local_name(name) do
    case prefix_size(name, 0) do
      nil -> name
      size -> binary_part(name, size + 1, byte_size(name) - size - 1)
    end
  end

  defp prefix_size(<<?:, _rest::binary>>, size), do: size
  defp prefix_size(<<_char, rest::binary>>, size), do: prefix_size(rest, size + 1)
  defp prefix_size(<<>>, _size), do: nil
end
