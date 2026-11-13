defmodule SpaceTAP.VOTable do
  @moduledoc false

  # Reads a VOTable document (VOTable 1.5) the way DALI 1.1 §4.4 lays out a
  # result: one RESOURCE of type results, holding an INFO named QUERY_STATUS
  # and a TABLE whose FIELDs describe the columns and whose DATA holds the
  # rows, in TABLEDATA, BINARY or BINARY2 (ADR 0005).
  #
  # It reads in two steps. Saxy's events collect the parts of the result
  # (ADR 0008), and decode/1 then turns them into fields and rows. A service
  # that writes rows as it reads them reports a failure in an ERROR status
  # after the table, which may then be cut short (DALI §4.4.2), so the status
  # is known only at the end, and an ERROR comes back without reading the
  # table.

  @behaviour Saxy.Handler

  alias SpaceTAP.Field
  alias SpaceTAP.VOTable.Binary
  alias SpaceTAP.VOTable.Value

  @type table :: %{fields: [Field.t()], rows: [[term()]], overflow: boolean()}

  # The twelve datatypes of VOTable 1.5 §2.1, by the name a FIELD gives them.
  @datatypes Map.new(
               ~w(boolean bit unsignedByte short int long char unicodeChar float double floatComplex doubleComplex)a,
               &{Atom.to_string(&1), &1}
             )

  @statuses ["OK", "ERROR", "OVERFLOW"]

  # The elements whose text is read.
  @text_roles [:status, :description, :td, :stream]

  @spec parse(binary()) :: {:ok, table()} | {:query_error, String.t()} | {:error, String.t()}
  def parse(xml) when is_binary(xml) do
    document = %{
      stack: [],
      text: [],
      results: 0,
      statuses: [],
      tables: 0,
      fields: [],
      data: nil,
      rows: [],
      row: [],
      encoding: nil,
      stream: nil
    }

    case Saxy.parse_string(xml, __MODULE__, document, expand_entity: {__MODULE__, :entity, []}) do
      {:ok, document} -> decode(document)
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

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, %{stack: stack} = document) do
    role = role(List.first(stack), local_name(name), attributes)
    document = %{document | stack: [role | stack]}
    {:ok, start(role, attributes, document)}
  end

  def handle_event(:characters, chars, %{stack: [role | _roles], text: text} = document)
      when role in @text_roles do
    {:ok, %{document | text: [text, chars]}}
  end

  def handle_event(:end_element, _name, %{stack: [role | roles]} = document) do
    {:ok, finish(role, %{document | stack: roles})}
  end

  def handle_event(_event, _data, document), do: {:ok, document}

  #####################
  # Private functions #
  #####################

  # The role of an element follows from its name and the role of its parent,
  # so an element only counts where VOTable puts it: a DESCRIPTION is a
  # field's only inside a FIELD of the result's TABLE, not inside a PARAM.
  # Element names are matched without their namespace prefix, which changes
  # with the VOTable version.
  defp role(nil, "VOTABLE", _attributes), do: :votable

  # The result of the query is in the RESOURCE of type results (DALI §4.4).
  # Others, such as the DataLink service descriptors Gaia adds after it, are
  # skipped.
  defp role(:votable, "RESOURCE", attributes) do
    if attribute(attributes, "type") == "results", do: :results, else: :other
  end

  # Services add other INFOs, such as the query (DALI §4.4.3), so the status
  # is found by name.
  defp role(:results, "INFO", attributes) do
    if attribute(attributes, "name") == "QUERY_STATUS", do: :status, else: :other
  end

  defp role(:results, "TABLE", _attributes), do: :table
  defp role(:table, "FIELD", _attributes), do: :field
  defp role(:field, "DESCRIPTION", _attributes), do: :description
  defp role(:field, "VALUES", _attributes), do: :values
  defp role(:table, "DATA", _attributes), do: :data
  defp role(:data, "TABLEDATA", _attributes), do: :tabledata
  defp role(:data, "BINARY", _attributes), do: :binary
  defp role(:data, "BINARY2", _attributes), do: :binary2
  defp role(:data, "FITS", _attributes), do: :fits
  defp role(:tabledata, "TR", _attributes), do: :tr
  defp role(:tr, "TD", _attributes), do: :td

  defp role(serialization, "STREAM", _attributes) when serialization in [:binary, :binary2],
    do: :stream

  defp role(_parent, _name, _attributes), do: :other

  defp local_name(name) do
    case :binary.split(name, ":") do
      [_prefix, local] -> local
      [local] -> local
    end
  end

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp start(:results, _attributes, document), do: %{document | results: document.results + 1}
  defp start(:table, _attributes, document), do: %{document | tables: document.tables + 1}

  # The value of a status is OK, ERROR or OVERFLOW, and its content is the
  # message (DALI §4.4).
  defp start(:status, attributes, document) do
    status = {attribute(attributes, "value"), ""}
    %{document | statuses: [status | document.statuses], text: []}
  end

  defp start(:field, attributes, document) do
    %{document | fields: [Map.new(attributes) | document.fields]}
  end

  # The null attribute of VALUES marks a cell with no data (§4.7).
  defp start(:values, attributes, %{fields: [field | fields]} = document) do
    %{document | fields: [Map.put(field, "null", attribute(attributes, "null")) | fields]}
  end

  # The child of DATA says how the rows are written (ADR 0005).
  defp start(serialization, _attributes, document)
       when serialization in [:tabledata, :binary, :binary2, :fits],
       do: %{document | data: serialization}

  defp start(:tr, _attributes, document), do: %{document | row: []}

  # VOTable 1.5 lets a TD hold its value in base64 (§5.1).
  defp start(:td, attributes, document),
    do: %{document | text: [], encoding: attribute(attributes, "encoding")}

  # A STREAM holds the rows in its content or points to them with href (§5.6).
  defp start(:stream, attributes, document) do
    stream = {attribute(attributes, "href"), attribute(attributes, "encoding"), []}
    %{document | stream: stream, text: []}
  end

  defp start(:description, _attributes, document), do: %{document | text: []}
  defp start(_role, _attributes, document), do: document

  defp finish(:status, %{statuses: [{value, _message} | statuses]} = document) do
    message = document.text |> IO.iodata_to_binary() |> String.trim()
    %{document | statuses: [{value, message} | statuses]}
  end

  # astropy trims a description too: KOA writes each one in a CDATA section
  # with a space at each end.
  defp finish(:description, %{fields: [field | fields]} = document) do
    description = document.text |> IO.iodata_to_binary() |> String.trim()
    %{document | fields: [Map.put(field, "description", description) | fields]}
  end

  defp finish(:td, %{encoding: nil} = document) do
    %{document | row: [IO.iodata_to_binary(document.text) | document.row]}
  end

  defp finish(:td, document),
    do: %{document | row: [{:encoding, document.encoding} | document.row]}

  defp finish(:tr, document), do: %{document | rows: [Enum.reverse(document.row) | document.rows]}

  defp finish(:stream, %{stream: {href, encoding, _text}} = document),
    do: %{document | stream: {href, encoding, document.text}}

  defp finish(_role, document), do: document

  defp decode(%{results: 0}), do: {:error, ~s(the document has no RESOURCE of type "results")}

  defp decode(%{results: results}) when results > 1,
    do: {:error, ~s(the document has more than one RESOURCE of type "results")}

  defp decode(%{statuses: []}), do: {:error, "the results RESOURCE has no QUERY_STATUS"}

  # An OVERFLOW or an ERROR may come before the table or after it, where it
  # follows an OK (DALI §4.4.1, §4.4.2), so any one of them counts.
  defp decode(document) do
    case Enum.find(document.statuses, fn {value, _message} -> value not in @statuses end) do
      {value, _message} -> {:error, "unknown QUERY_STATUS #{inspect(value)}"}
      nil -> status(document)
    end
  end

  defp status(document) do
    case List.keyfind(document.statuses, "ERROR", 0) do
      {"ERROR", message} -> {:query_error, message}
      nil -> table(document)
    end
  end

  # An ADQL query gives a single table (TAP 1.1 §3.2).
  defp table(%{tables: 0}), do: {:error, "the results RESOURCE has no TABLE"}

  defp table(%{tables: tables}) when tables > 1,
    do: {:error, "the results RESOURCE has more than one TABLE"}

  defp table(document) do
    with {:ok, fields} <- fields(Enum.reverse(document.fields), []),
         {:ok, rows} <- rows(document, fields) do
      overflow = Enum.any?(document.statuses, &match?({"OVERFLOW", _message}, &1))
      {:ok, %{fields: fields, rows: rows, overflow: overflow}}
    end
  end

  defp fields([], fields), do: {:ok, Enum.reverse(fields)}

  defp fields([attributes | rest], fields) do
    with {:ok, field} <- field(attributes), do: fields(rest, [field | fields])
  end

  # A FIELD needs a name and a datatype (§4), which is one of the twelve of
  # §2.1 (Q13), and is checked as it is read, so a table with no rows can't
  # hide a field SpaceTAP couldn't read.
  defp field(%{"name" => name} = attributes) do
    case Map.fetch(attributes, "datatype") do
      {:ok, datatype} when is_map_key(@datatypes, datatype) ->
        field = %Field{
          name: name,
          datatype: Map.fetch!(@datatypes, datatype),
          arraysize: attributes["arraysize"],
          xtype: attributes["xtype"],
          unit: attributes["unit"],
          ucd: attributes["ucd"],
          utype: attributes["utype"],
          description: attributes["description"],
          null: attributes["null"]
        }

        with :ok <- Value.check_field(field), do: {:ok, field}

      {:ok, datatype} ->
        {:error, ~s(field #{inspect(name)}: unknown datatype #{inspect(datatype)})}

      :error ->
        {:error, ~s(field #{inspect(name)} has no datatype)}
    end
  end

  defp field(_attributes), do: {:error, "a FIELD has no name"}

  # DATA is optional in a TABLE, which then has no rows (VOTable 1.5 §3.8).
  defp rows(%{data: nil}, _fields), do: {:ok, []}

  defp rows(%{data: :tabledata, rows: rows}, fields) do
    text_rows(Enum.reverse(rows), fields, length(fields), 1, [])
  end

  # FITS is a file format of its own, which SpaceTAP doesn't read (ADR 0005).
  defp rows(%{data: :fits}, _fields), do: {:error, "the FITS serialization is not supported"}

  defp rows(%{data: serialization, stream: stream}, fields) do
    with {:ok, bytes} <- stream(stream, serialization),
         do: Binary.rows(bytes, fields, serialization)
  end

  # Each TR has a TD for each FIELD, in their order (§5.1).
  defp text_rows([], _fields, _count, _number, rows), do: {:ok, Enum.reverse(rows)}

  defp text_rows([texts | rest], fields, count, number, rows) do
    with {:ok, row} <- text_row(texts, fields, count, number),
         do: text_rows(rest, fields, count, number + 1, [row | rows])
  end

  defp text_row(texts, fields, count, number) do
    case length(texts) do
      ^count -> cells(texts, fields, number, [])
      cells -> {:error, "row #{number} has #{cells} cells for #{count} fields"}
    end
  end

  defp cells([], [], _number, values), do: {:ok, Enum.reverse(values)}

  defp cells([{:encoding, encoding} | _texts], [field | _fields], number, _values) do
    {:error,
     ~s(row #{number}, field #{inspect(field.name)}: the TD encoding #{inspect(encoding)} is not supported)}
  end

  defp cells([text | texts], [field | fields], number, values) do
    case Value.parse_text(text, field) do
      {:ok, value} -> cells(texts, fields, number, [value | values])
      {:error, message} -> {:error, "row #{number}, " <> message}
    end
  end

  # Only a STREAM inside the document is read, and inside an XML document its
  # bytes can only be in base64 (§5.6), which services break into lines.
  # Following an href would be another request, made by the parser.
  defp stream(nil, serialization),
    do: {:error, "the #{serialization |> Atom.to_string() |> String.upcase()} has no STREAM"}

  defp stream({href, _encoding, _text}, _serialization) when is_binary(href),
    do: {:error, "a STREAM with an href is not supported"}

  defp stream({nil, "base64", text}, _serialization) do
    case text |> IO.iodata_to_binary() |> Base.decode64(ignore: :whitespace) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, "the STREAM is not valid base64"}
    end
  end

  defp stream({nil, nil, _text}, _serialization), do: {:error, "the STREAM has no encoding"}

  defp stream({nil, encoding, _text}, _serialization),
    do: {:error, ~s(the STREAM encoding #{inspect(encoding)} is not supported)}
end
