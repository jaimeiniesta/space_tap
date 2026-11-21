defmodule SpaceTAP.XMLTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.{UWS, VOSI, VOTable, XML}

  @fixtures Path.expand("../fixtures", __DIR__)
  @bom <<0xEF, 0xBB, 0xBF>>

  # A reader of a list of items: the kind and the text of each item of the
  # list, and nothing from anywhere else.
  defmodule Items do
    @behaviour XML

    def parse(xml), do: XML.parse(xml, __MODULE__, %{kinds: [], items: []})

    @impl XML
    def role(nil, "list", _attributes), do: :list
    def role(:list, "item", _attributes), do: :item
    def role(_parent, _name, _attributes), do: :other

    @impl XML
    def text_roles, do: [:item]

    @impl XML
    def start(:item, attributes, document),
      do: %{document | kinds: [XML.attribute(attributes, "kind") | document.kinds]}

    def start(_role, _attributes, document), do: document

    @impl XML
    def finish(:item, text, document), do: %{document | items: [text | document.items]}
    def finish(_role, _text, document), do: document
  end

  describe "parse/3" do
    test "gives an element the role its name and its parent's role say, whatever the prefix" do
      xml = ~s"""
      <x:list xmlns:x="urn:x">
        <x:item kind="a">one</x:item>
        <other><item kind="b">not an item of the list</item></other>
        <item>two</item>
      </x:list>
      """

      assert Items.parse(xml) == {:ok, %{kinds: [nil, "a"], items: ["two", "one"]}}
    end

    test "keeps the text directly inside an element with a text role, and nothing else" do
      xml = ~s(<list><item>one <b>and</b> two</item><item/><b>three</b></list>)

      assert Items.parse(xml) == {:ok, %{kinds: [nil, nil], items: ["", "one  two"]}}
    end

    test "matches attributes by their local name too" do
      xml = ~s(<list xmlns:x="urn:x"><item x:kind="a" kind="b">one</item></list>)

      assert Items.parse(xml) == {:ok, %{kinds: ["a"], items: ["one"]}}
    end

    test "gives the reader's document back when the document holds nothing for it" do
      assert Items.parse("<other><item>one</item></other>") == {:ok, %{kinds: [], items: []}}
    end

    test "reads a document that begins with a UTF-8 byte order mark as one without (XML 1.0 §4.3.3)" do
      for xml <- [
            ~s(<?xml version="1.0" encoding="UTF-8"?><list><item>one</item></list>),
            ~s(<list><item>one</item></list>)
          ] do
        assert Items.parse(@bom <> xml) == Items.parse(xml)
        assert {:ok, %{items: ["one"]}} = Items.parse(@bom <> xml)
      end

      for {reader, document} <- [
            {&UWS.parse/1, fixture("gavo", "jobs/completed.xml")},
            {&VOTable.parse/1, fixture("gavo", "hipparcos.xml")},
            {&VOSI.availability/1, fixture("gavo", "availability.xml")}
          ] do
        assert {:ok, _read} = reader.(document)
        assert reader.(@bom <> document) == reader.(document)
      end

      # A UTF-16 document, which must begin with its mark, isn't read.
      assert {:error, "invalid XML: " <> _reason} = Items.parse(<<0xFF, 0xFE>> <> "<list/>")
    end

    test "rejects invalid XML, and entities XML doesn't predefine" do
      assert {:error, "invalid XML: " <> _reason} = Items.parse("<list><item>one</list>")

      assert Items.parse("<list><item>&nbsp;</item></list>") ==
               {:error, "invalid XML: &nbsp; is not a predefined entity"}

      assert Items.parse("<list><item>&amp;&#65;</item></list>") ==
               {:ok, %{kinds: [nil], items: ["&A"]}}
    end
  end

  defp fixture(service, name), do: File.read!(Path.join([@fixtures, service, name]))
end
