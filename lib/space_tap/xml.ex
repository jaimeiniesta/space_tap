defmodule SpaceTAP.XML do
  @moduledoc false

  # What the readers of XML documents share, SpaceTAP.VOTable for results
  # and error documents, SpaceTAP.UWS for job documents and SpaceTAP.VOSI
  # for capabilities and availability: parsing with Saxy (ADR 0008) without
  # expanding entities, and reading a document by the role of each element.
  # The role follows from the element's local name, without the namespace
  # prefix, which changes from one service to another, and from the role of
  # its parent, so an element only counts where its standard puts it: a
  # phase is the job's only as a child of the job, and a DESCRIPTION a
  # field's only inside a FIELD of the result's TABLE.
  #
  # A reader is a module with the four callbacks below: what the roles are,
  # which of them have text worth keeping, and what to keep from an element
  # when it starts and when it ends. This module is the Saxy handler for all
  # of them, and keeps the stack of roles and the text itself.

  @behaviour Saxy.Handler

  @type role :: atom()
  @type attributes :: [{String.t(), String.t()}]

  # The role of an element, from the role of its parent, nil for the root,
  # its local name and its attributes. An element that doesn't count gets a
  # role too, such as :other, since the roles of its children follow from it.
  @callback role(parent :: role() | nil, name :: String.t(), attributes()) :: role()

  # The roles whose text, the characters directly inside the element, is
  # kept and given to finish/3 as a binary; the others get nil.
  @callback text_roles() :: [role()]

  @callback start(role(), attributes(), document) :: document when document: term()

  @callback finish(role(), text :: String.t() | nil, document) :: document
            when document: term()

  # The stack holds the role of each open element and whether its text is
  # kept, decided once when it starts: a large TABLEDATA has millions of
  # events, and a map key is checked faster than a list is searched.
  defstruct [:reader, :text_roles, :document, stack: [], text: []]

  @spec parse(binary(), module(), document) :: {:ok, document} | {:error, String.t()}
        when document: term()
  def parse(xml, reader, document) do
    text_roles = Map.new(reader.text_roles(), &{&1, true})
    state = %__MODULE__{reader: reader, text_roles: text_roles, document: document}
    options = [expand_entity: {__MODULE__, :entity, []}]

    case Saxy.parse_string(without_bom(xml), __MODULE__, state, options) do
      {:ok, state} -> {:ok, state.document}
      {:error, exception} -> {:error, "invalid XML: " <> Exception.message(exception)}
    end
  catch
    {:entity, name} -> {:error, "invalid XML: &#{name}; is not a predefined entity"}
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, %{reader: reader, stack: stack} = state) do
    role = reader.role(parent(stack), local_name(name), attributes)
    document = reader.start(role, attributes, state.document)

    if is_map_key(state.text_roles, role),
      do: {:ok, %{state | stack: [{role, true} | stack], text: [], document: document}},
      else: {:ok, %{state | stack: [{role, false} | stack], document: document}}
  end

  def handle_event(:characters, chars, %{stack: [{_role, true} | _stack]} = state) do
    {:ok, %{state | text: [state.text, chars]}}
  end

  def handle_event(:end_element, _name, %{stack: [{role, kept} | stack]} = state) do
    text = if kept, do: IO.iodata_to_binary(state.text), else: nil
    document = state.reader.finish(role, text, state.document)
    {:ok, %{state | stack: stack, document: document}}
  end

  def handle_event(_event, _data, state), do: {:ok, state}

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

  # The value of an attribute, matched by local name as elements are: the
  # href of a result is an XLink attribute, usually written xlink:href. Most
  # elements, such as a TD, have no attributes.
  @spec attribute(attributes(), String.t()) :: String.t() | nil
  def attribute([], _name), do: nil

  def attribute(attributes, name) do
    Enum.find_value(attributes, fn {key, value} -> local_name(key) == name && value end)
  end

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

  defp parent([{role, _kept} | _stack]), do: role
  defp parent([]), do: nil

  # XML 1.0 §4.3.3 lets a UTF-8 document begin with a byte order mark, which
  # Saxy rejects as a byte before the first element. No known service sends
  # one, and a UTF-16 document, which must begin with its mark, isn't read:
  # Saxy reads UTF-8.
  defp without_bom(<<0xEF, 0xBB, 0xBF, xml::binary>>), do: xml
  defp without_bom(xml), do: xml
end
