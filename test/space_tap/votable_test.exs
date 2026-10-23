defmodule SpaceTAP.VOTableTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.VOTable

  @fixtures Path.expand("../fixtures/gaia", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  describe "query_status/1" do
    test "reads OK from Gaia's result when nothing was truncated" do
      assert VOTable.query_status(fixture("ok.xml")) == {:ok, {"OK", ""}}
    end

    test "reads Gaia's syntax error: trimmed, multi-line, entities decoded" do
      assert {:ok, {"ERROR", message}} = VOTable.query_status(fixture("syntax_error.xml"))

      assert message =~ ~r/\ACannot parse query 'SELEC TOP 3 source_id/
      assert message =~ ~s(Encountered " <REGULAR_IDENTIFIER> "SELEC "")
      assert message =~ ~r/\nWas expecting one of:\n/
      assert message =~ ~r/"SELECT" \.\.\.\z/
    end

    test "reads Gaia's unknown-table error, ignoring the INFOs after it" do
      assert {:ok, {"ERROR", message}} = VOTable.query_status(fixture("unknown_table.xml"))

      assert message =~ ~s(- Unknown table "gaiadr3.no_such_table" !)
      assert message =~ ~r/- Unknown column "source_id" !\z/
    end

    test "returns the last QUERY_STATUS: OVERFLOW after the table, not OK before it" do
      assert VOTable.query_status(fixture("overflow.xml")) == {:ok, {"OVERFLOW", ""}}
    end

    test "decodes predefined entities and character references in the message" do
      xml =
        ~s(<VOTABLE><INFO name="QUERY_STATUS" value="ERROR">a &lt; b&#10;&apos;c&apos;</INFO></VOTABLE>)

      assert VOTable.query_status(xml) == {:ok, {"ERROR", "a < b\n'c'"}}
    end

    test "returns nil when the document has no QUERY_STATUS" do
      xml = ~s(<VOTABLE><RESOURCE><INFO name="Action" value="x"/></RESOURCE></VOTABLE>)

      assert VOTable.query_status(xml) == {:ok, nil}
    end

    test "fails on malformed XML" do
      assert {:error, "invalid XML: " <> _} = VOTable.query_status("<VOTABLE><INFO></VOTABLE>")
    end

    test "says the document ended early when it is cut off" do
      xml = ~s(<VOTABLE><INFO name="QUERY_STATUS" value="ERROR">Cannot pa)

      assert VOTable.query_status(xml) == {:error, "invalid XML: unexpected end of document"}
    end

    test "fails on content after the root element" do
      xml = ~s(<VOTABLE><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></VOTABLE>\njunk)

      assert VOTable.query_status(xml) == {:error, "invalid XML: content after the root element"}
    end

    test "fails on a second document instead of reading only the first" do
      xml = """
      <VOTABLE><INFO name="QUERY_STATUS" value="OK"/></VOTABLE>
      <VOTABLE><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></VOTABLE>
      """

      assert VOTable.query_status(xml) == {:error, "invalid XML: content after the root element"}
    end

    test "fails on content between comments or processing instructions after the root element" do
      for misc <- ["<!-- a -->junk<!-- b -->", "<?a x?>junk<?b y?>"] do
        xml = ~s(<VOTABLE><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></VOTABLE>) <> misc

        assert VOTable.query_status(xml) ==
                 {:error, "invalid XML: content after the root element"}
      end
    end

    test "accepts whitespace, comments and processing instructions after the root element" do
      xml = """
      <VOTABLE><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></VOTABLE>
      <!-- generated -->
      <?foo bar?>
      """

      assert VOTable.query_status(xml) == {:ok, {"ERROR", "failed"}}
    end

    test "fails on a body that is not XML, such as an HTML error page" do
      assert {:error, "invalid XML: " <> _} = VOTable.query_status("Bad Gateway")
    end

    test "refuses a document that declares entities instead of expanding them" do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE VOTABLE [<!ENTITY boom "boom boom boom">]>
      <VOTABLE><INFO name="QUERY_STATUS" value="ERROR">&boom;</INFO></VOTABLE>
      """

      assert {:error, "invalid XML: " <> _} = VOTable.query_status(xml)
    end

    test "does not load an external DTD" do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE VOTABLE SYSTEM "http://www.ivoa.net/xml/VOTable/VOTable.dtd">
      <VOTABLE><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></VOTABLE>
      """

      assert VOTable.query_status(xml) == {:ok, {"ERROR", "failed"}}
    end
  end
end
