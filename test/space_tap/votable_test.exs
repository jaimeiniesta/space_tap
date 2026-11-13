defmodule SpaceTAP.VOTableTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.Field
  alias SpaceTAP.VOTable

  @fixtures Path.expand("../fixtures", __DIR__)

  # The expected values of the services' documents are what astropy 8.0.2
  # reads from them, with the values ADR 0007 picks where they differ: nil for
  # an empty string.
  describe "parse/1" do
    test "reads the fields and rows of MAST's TABLEDATA result" do
      assert VOTable.parse(fixture("tables.xml", "mast")) ==
               {:ok,
                %{
                  fields: [
                    %Field{
                      name: "table_name",
                      datatype: :char,
                      arraysize: "*",
                      description: "Fully qualified table name"
                    }
                  ],
                  rows: [["tap_schema.schemas"], ["tap_schema.tables"], ["tap_schema.columns"]],
                  overflow: false
                }}
    end

    test "reads the TABLEDATA rows of IRSA, ESO and CADC, whose arraysize is a maximum (§5.1)" do
      irsa = [
        ["fp_psc", "ra", "double", "deg", "right ascension (J2000 decimal deg)"],
        ["fp_psc", "dec", "double", "deg", "declination (J2000 decimal deg)"],
        [
          "fp_psc",
          "err_maj",
          "float",
          "arcsec",
          "Semi-major axis length of the one sigma position uncertainty ellipse"
        ],
        [
          "fp_psc",
          "err_min",
          "float",
          "arcsec",
          "Semi-minor axis length of the one sigma position uncertainty ellipse"
        ],
        ["fp_psc", "err_ang", "int", "deg", "angle of error ellipse major axis (E of N)"]
      ]

      eso = [
        ["962640", "28Tau", 57.296784, 24.13606, "XSHOOTER", "spectrum", 5.336599999999999e-7],
        ["962640", "28Tau", 57.296784, 24.13606, "XSHOOTER", "spectrum", 2.9892000000000003e-7],
        ["962640", "28Tau", 57.296784, 24.13606, "XSHOOTER", "spectrum", 9.9402e-7],
        ["962645", "28Tau", 57.296684, 24.13595, "XSHOOTER", "spectrum", 5.336599999999999e-7],
        ["962645", "28Tau", 57.296684, 24.13595, "XSHOOTER", "spectrum", 9.9402e-7]
      ]

      hst = ["HST", "NPL38", 56.96050459498824, 23.913671015486443, "WFPC2/PC", 7.9373e-7]

      cadc = [
        ["u63e0204r" | hst],
        ["u63e0204r" | hst],
        ["u63e0204r" | hst],
        [
          "hst_8701_02_wfpc2_pc_f814w_u63e0202",
          "HST",
          "NPL38",
          56.971377254675865,
          23.916483663589716,
          "WFPC2/PC",
          7.1351e-7
        ],
        ["u63e0203r" | hst]
      ]

      for {service, file, rows} <- [
            {"irsa", "columns.xml", irsa},
            {"eso", "obscore.xml", eso},
            {"cadc", "obscore.xml", cadc}
          ] do
        assert {:ok, %{rows: ^rows}} = VOTable.parse(fixture(file, service))
      end
    end

    test "reads GAVO's BINARY result, with the null value of a field (§5.3, §4.7)" do
      assert {:ok, %{fields: fields, rows: rows, overflow: false}} =
               VOTable.parse(fixture("hipparcos.xml", "gavo"))

      assert fields == [
               %Field{
                 name: "hipno",
                 datatype: :int,
                 ucd: "meta.id;meta.main",
                 description: "Identifier (HIP number)",
                 null: "-2147483648"
               },
               %Field{
                 name: "ra",
                 datatype: :double,
                 unit: "deg",
                 ucd: "pos.eq.ra;meta.main",
                 description: "Right ascension ICRS (Epoch J1991.25)"
               },
               %Field{
                 name: "dec",
                 datatype: :double,
                 unit: "deg",
                 ucd: "pos.eq.dec;meta.main",
                 description: "Declination ICRS (Epoch J1991.25)"
               },
               %Field{
                 name: "vmag",
                 datatype: :float,
                 unit: "mag",
                 ucd: "phot.mag;em.opt.V",
                 description: "Magnitude in Johnson V"
               },
               %Field{
                 name: "parallax",
                 datatype: :float,
                 unit: "deg",
                 ucd: "pos.parallax.trig",
                 description: "Trigonometric parallax"
               },
               %Field{
                 name: "SpType",
                 datatype: :char,
                 arraysize: "*",
                 ucd: "src.spType",
                 description: "Spectral type from various sources"
               }
             ]

      assert rows == [
               [1, 9.1185e-4, 1.08901332, 9.100000381469727, 9.833332796915784e-7, "F5"],
               [2, 0.00379737, -19.49883745, 9.270000457763672, 6.083333119022427e-6, "K3V"],
               [3, 0.00500795, 38.85928608, 6.610000133514404, 7.805555810591613e-7, "B9"],
               [4, 0.0083817, -51.89354612, 8.0600004196167, 2.1527778244490037e-6, "F0V"],
               [5, 0.00996534, -40.5912244, 8.550000190734863, 7.972222419994068e-7, "G8III"]
             ]
    end

    test "reads Gaia's BINARY2 result, skipping the PARAMs and RESOURCEs around the table (§5.4)" do
      assert {:ok, %{fields: fields, rows: rows, overflow: false}} =
               VOTable.parse(fixture("pleiades.xml"))

      assert fields == [
               %Field{
                 name: "source_id",
                 datatype: :long,
                 ucd: "meta.id",
                 description: "Unique source identifier (unique within a particular Data Release)"
               },
               %Field{
                 name: "designation",
                 datatype: :char,
                 arraysize: "*",
                 ucd: "meta.id;meta.main",
                 description: "Unique source designation (unique across all Data Releases)"
               },
               %Field{
                 name: "ra",
                 datatype: :double,
                 unit: "deg",
                 ucd: "pos.eq.ra;meta.main",
                 utype: "stc:AstroCoords.Position3D.Value3.C1",
                 description: "Right ascension"
               },
               %Field{
                 name: "dec",
                 datatype: :double,
                 unit: "deg",
                 ucd: "pos.eq.dec;meta.main",
                 utype: "stc:AstroCoords.Position3D.Value3.C2",
                 description: "Declination"
               },
               %Field{
                 name: "parallax",
                 datatype: :double,
                 unit: "mas",
                 ucd: "pos.parallax.trig",
                 description: "Parallax"
               },
               %Field{
                 name: "phot_g_mean_mag",
                 datatype: :float,
                 unit: "mag",
                 ucd: "phot.mag;em.opt",
                 description: "G-band mean magnitude"
               }
             ]

      assert rows == [
               [
                 66_526_127_137_440_128,
                 "Gaia DR3 66526127137440128",
                 57.29068893293528,
                 24.053211829998986,
                 8.118448445799721,
                 3.6157946586608887
               ],
               [
                 65_271_996_684_817_280,
                 "Gaia DR3 65271996684817280",
                 56.2190045645284,
                 24.11313304360812,
                 8.345685150896063,
                 3.6982085704803467
               ],
               [
                 65_283_232_316_451_328,
                 "Gaia DR3 65283232316451328",
                 56.45679586432521,
                 24.36754142471917,
                 7.671309961502887,
                 3.863348960876465
               ],
               [
                 65_205_373_152_172_032,
                 "Gaia DR3 65205373152172032",
                 56.58167144917715,
                 23.94814381017594,
                 7.067028703633884,
                 4.172741889953613
               ],
               [
                 65_296_907_494_549_120,
                 "Gaia DR3 65296907494549120",
                 56.302162856141784,
                 24.46706395730414,
                 9.544445082693732,
                 4.261021614074707
               ]
             ]
    end

    test "sets overflow from the OVERFLOW status Gaia writes after the table (DALI §4.4.1)" do
      assert {:ok, %{rows: rows, overflow: true}} = VOTable.parse(fixture("overflow.xml"))
      assert length(rows) == 3
    end

    test "returns the message of Gaia's ERROR status, trimmed and with its entities decoded (DALI §4.4.2)" do
      assert {:query_error, message} = VOTable.parse(fixture("syntax_error.xml"))

      assert message =~ ~r/\ACannot parse query 'SELEC TOP 3 source_id/
      assert message =~ ~s(Encountered " <REGULAR_IDENTIFIER> "SELEC "")
      assert message =~ ~r/"SELECT" \.\.\.\z/
    end

    test "returns an ERROR written after the table without reading the table, which may be cut short (DALI §4.4.2)" do
      xml = """
      <VOTABLE><RESOURCE type="results">
        <INFO name="QUERY_STATUS" value="OK"/>
        <TABLE>
          <FIELD name="id" datatype="int"/>
          <DATA><TABLEDATA><TR><TD>1</TD></TR><TR><TD>2.</TD></TR></TABLEDATA></DATA>
        </TABLE>
        <INFO name="QUERY_STATUS" value="ERROR">unexpected IO error</INFO>
      </RESOURCE></VOTABLE>
      """

      assert VOTable.parse(xml) == {:query_error, "unexpected IO error"}
    end

    test "reads only the RESOURCE of type results and the QUERY_STATUS directly inside it (DALI §4.4)" do
      xml = """
      <VOTABLE>
        <INFO name="QUERY_STATUS" value="ERROR">not the result's</INFO>
        <RESOURCE type="meta"><INFO name="QUERY_STATUS" value="ERROR">nor this</INFO></RESOURCE>
        <RESOURCE type="results">
          <INFO name="QUERY_STATUS" value="OK"/>
          <RESOURCE><INFO name="QUERY_STATUS" value="OVERFLOW"/></RESOURCE>
          <TABLE><FIELD name="id" datatype="int"/></TABLE>
        </RESOURCE>
      </VOTABLE>
      """

      assert VOTable.parse(xml) ==
               {:ok, %{fields: [%Field{name: "id", datatype: :int}], rows: [], overflow: false}}
    end

    test "rejects a document without exactly one RESOURCE of type results (DALI §4.4)" do
      status = ~s(<INFO name="QUERY_STATUS" value="ERROR">failed</INFO>)

      assert VOTable.parse("<VOTABLE><RESOURCE>#{status}</RESOURCE></VOTABLE>") ==
               {:error, ~s(the document has no RESOURCE of type "results")}

      assert VOTable.parse(fixture("sync_get.xml")) ==
               {:error, ~s(the document has no RESOURCE of type "results")}

      results = ~s(<RESOURCE type="results">#{status}</RESOURCE>)

      assert VOTable.parse("<VOTABLE>#{results}#{results}</VOTABLE>") ==
               {:error, ~s(the document has more than one RESOURCE of type "results")}
    end

    test "rejects a results RESOURCE without a QUERY_STATUS, or with a status DALI doesn't define (§4.4)" do
      table = ~s(<TABLE><FIELD name="id" datatype="int"/></TABLE>)

      assert VOTable.parse(~s(<VOTABLE><RESOURCE type="results">#{table}</RESOURCE></VOTABLE>)) ==
               {:error, "the results RESOURCE has no QUERY_STATUS"}

      xml =
        ~s(<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="DONE"/>#{table}</RESOURCE></VOTABLE>)

      assert VOTable.parse(xml) == {:error, ~s(unknown QUERY_STATUS "DONE")}
    end

    test "rejects a successful result without exactly one TABLE (TAP §3.2)" do
      ok = ~s(<INFO name="QUERY_STATUS" value="OK"/>)
      table = ~s(<TABLE><FIELD name="id" datatype="int"/></TABLE>)

      assert VOTable.parse(~s(<VOTABLE><RESOURCE type="results">#{ok}</RESOURCE></VOTABLE>)) ==
               {:error, "the results RESOURCE has no TABLE"}

      assert VOTable.parse(
               ~s(<VOTABLE><RESOURCE type="results">#{ok}#{table}#{table}</RESOURCE></VOTABLE>)
             ) == {:error, "the results RESOURCE has more than one TABLE"}
    end

    test "rejects a FIELD without a name, or without one of the twelve datatypes (§2.1, §4)" do
      for {field, message} <- [
            {~s(<FIELD name="mag" datatype="real"/>), ~s(field "mag": unknown datatype "real")},
            {~s(<FIELD name="mag"/>), ~s(field "mag" has no datatype)},
            {~s(<FIELD datatype="float"/>), "a FIELD has no name"}
          ] do
        assert VOTable.parse(result(field)) == {:error, message}
      end
    end

    test "rejects a FIELD SpaceTAP can't read even when no cell uses it, as with no rows or an empty TD" do
      for {field, message} <- [
            {~s(<FIELD name="mag" datatype="float" arraysize="abc"/>),
             ~s(field "mag": "abc" is not a valid arraysize)},
            {~s(<FIELD name="mag" datatype="float"><VALUES null="none"/></FIELD>),
             ~s(field "mag": the null value "none" is not a valid float)},
            {~s(<FIELD name="flags" datatype="bit"/>),
             ~s(field "flags": the bit datatype is not supported)}
          ] do
        assert VOTable.parse(result(field)) == {:error, message}

        assert VOTable.parse(
                 result(field <> "<DATA><TABLEDATA><TR><TD/></TR></TABLEDATA></DATA>")
               ) ==
                 {:error, message}
      end
    end

    test "returns the first cell it can't read, with its row" do
      xml =
        result(
          ~s(<FIELD name="id" datatype="int"/><DATA><TABLEDATA><TR><TD>1</TD></TR><TR><TD>2.</TD></TR></TABLEDATA></DATA>)
        )

      assert VOTable.parse(xml) == {:error, ~s(row 2, field "id": "2." is not a valid int)}
    end

    test "rejects a TABLEDATA row with more or fewer cells than fields (§5.1)" do
      fields = ~s(<FIELD name="id" datatype="int"/><FIELD name="ra" datatype="double"/>)

      for {cells, count} <- [{"<TD>1</TD>", 1}, {"<TD>1</TD><TD>2</TD><TD>3</TD>", 3}] do
        xml =
          result(
            ~s(#{fields}<DATA><TABLEDATA><TR><TD>1</TD><TD>2</TD></TR><TR>#{cells}</TR></TABLEDATA></DATA>)
          )

        assert VOTable.parse(xml) == {:error, "row 2 has #{count} cells for 2 fields"}
      end
    end

    test "rejects data that isn't in the document in base64: FITS, a STREAM with an href or another encoding (ADR 0005, §5.6)" do
      field = ~s(<FIELD name="id" datatype="int"/>)

      for {data, message} <- [
            {~s(<FITS><STREAM encoding="base64">AAAA</STREAM></FITS>),
             "the FITS serialization is not supported"},
            {~s(<BINARY2><STREAM href="https://example.org/rows.bin"/></BINARY2>),
             "a STREAM with an href is not supported"},
            {~s(<BINARY><STREAM encoding="gzip">AAAA</STREAM></BINARY>),
             ~s(the STREAM encoding "gzip" is not supported)},
            {~s(<BINARY><STREAM>AAAA</STREAM></BINARY>), "the STREAM has no encoding"},
            {~s(<BINARY></BINARY>), "the BINARY has no STREAM"},
            {~s(<BINARY2><STREAM encoding="base64">AA*A</STREAM></BINARY2>),
             "the STREAM is not valid base64"}
          ] do
        assert VOTable.parse(result("#{field}<DATA>#{data}</DATA>")) == {:error, message}
      end
    end

    test "rejects a TD with an encoding, new in VOTable 1.5 (§5.1)" do
      xml =
        result(
          ~s(<FIELD name="id" datatype="int"/><DATA><TABLEDATA><TR><TD encoding="base64">AAAAAQ==</TD></TR></TABLEDATA></DATA>)
        )

      assert VOTable.parse(xml) ==
               {:error, ~s(row 1, field "id": the TD encoding "base64" is not supported)}
    end

    test "rejects a reference to an entity XML doesn't predefine, declared in a DTD or not (XML 1.0 §4.1, §5.1)" do
      declared = """
      <?xml version="1.0"?>
      <!DOCTYPE VOTABLE [<!ENTITY boom "boom boom boom">]>
      <VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">&boom;</INFO></RESOURCE></VOTABLE>
      """

      in_attribute =
        ~s(<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="&ok;"/></RESOURCE></VOTABLE>)

      assert VOTable.parse(declared) ==
               {:error, "invalid XML: &boom; is not a predefined entity"}

      assert VOTable.parse(in_attribute) ==
               {:error, "invalid XML: &ok; is not a predefined entity"}
    end

    test "decodes the predefined entities and character references" do
      xml =
        ~s(<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">a &lt; b&#10;&apos;c&apos;</INFO></RESOURCE></VOTABLE>)

      assert VOTable.parse(xml) == {:query_error, "a < b\n'c'"}
    end

    test "rejects a body that isn't a whole XML document" do
      ok =
        ~s(<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></RESOURCE></VOTABLE>)

      for xml <- [
            "Bad Gateway",
            "<VOTABLE><INFO></VOTABLE>",
            ~s(<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">Cannot pa),
            ok <> "\njunk",
            ok <> "\n" <> ok,
            ok <> "<!-- a -->junk<!-- b -->",
            ~s(<?xml?>) <> ok,
            ~s(<?xml version="1.0" encoding="ISO-8859-1"?>) <> ok
          ] do
        assert {:error, "invalid XML: " <> _reason} = VOTable.parse(xml)
      end
    end

    test "accepts whitespace, comments and processing instructions around the root element (XML 1.0 §2.8)" do
      xml = """
      <?xml-model href="VOTable.xsd"?>
      <VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></RESOURCE></VOTABLE>
      <!-- generated -->
      <?foo bar?>
      """

      assert VOTable.parse(xml) == {:query_error, "failed"}
    end

    test "doesn't load an external DTD" do
      xml = """
      <?xml version="1.0"?>
      <!DOCTYPE VOTABLE SYSTEM "http://www.ivoa.net/xml/VOTable/VOTable.dtd">
      <VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">failed</INFO></RESOURCE></VOTABLE>
      """

      assert VOTable.parse(xml) == {:query_error, "failed"}
    end

    test "reads Gaia's unknown-table error, ignoring the INFOs after it" do
      assert {:query_error, message} = VOTable.parse(fixture("unknown_table.xml"))

      assert message =~ ~s(- Unknown table "gaiadr3.no_such_table" !)
      assert message =~ ~r/- Unknown column "source_id" !\z/
    end

    test "reads GAVO's error, which starts with an xml-stylesheet instruction and no XML declaration" do
      assert VOTable.parse(fixture("syntax_error.xml", "gavo")) ==
               {:query_error,
                "Field query: Could not parse your query: Expected SELECT, found 'S'  (at char 0), (line:1, col:1)"}
    end

    test "matches elements by their local name, whatever their namespace prefix" do
      xml = """
      <v:VOTABLE xmlns:v="http://www.ivoa.net/xml/VOTable/v1.3">
        <v:RESOURCE type="results">
          <v:INFO name="QUERY_STATUS" value="OK"/>
          <v:TABLE>
            <v:FIELD name="id" datatype="int"/>
            <v:DATA><v:TABLEDATA><v:TR><v:TD>7</v:TD></v:TR></v:TABLEDATA></v:DATA>
          </v:TABLE>
        </v:RESOURCE>
      </v:VOTABLE>
      """

      assert {:ok, %{rows: [[7]]}} = VOTable.parse(xml)
    end

    test "reads NED's nulls in BINARY: NaN in a double and empty strings (§5.5, ADR 0007)" do
      assert {:ok, %{fields: fields, rows: rows}} = VOTable.parse(fixture("objdir.xml", "ned"))

      assert Enum.map(fields, &{&1.name, &1.datatype, &1.arraysize}) == [
               {"prefname", :char, "*"},
               {"prefphytype", :char, "*"},
               {"ra", :double, nil},
               {"dec", :double, nil},
               {"z", :double, nil},
               {"zflag", :char, "*"}
             ]

      assert rows == [
               ["2XMM J034620.0+241343", nil, 56.58365208333, 24.22884694444, nil, nil],
               ["2XMM J034620.5+241417", nil, 56.58550083333, 24.23827388889, nil, nil],
               ["2XMM J034659.3+241501", nil, 56.74729583333, 24.25043194444, nil, nil],
               ["2XMM J034705.1+241801", nil, 56.771365, 24.30052277778, nil, nil],
               ["2XMM J034705.1+240934", nil, 56.77154083333, 24.159675, nil, nil]
             ]
    end

    test "reads KOA's cells and descriptions written as CDATA, trimming the descriptions as astropy does" do
      assert {:ok, %{fields: fields, rows: rows}} = VOTable.parse(fixture("hires.xml", "koa"))

      assert Enum.map(fields, & &1.description) == [
               "Unique identifier for each file",
               "instrument name",
               "target-name",
               "RA in decimal degrees, J2000 equinox",
               "Declination in decimal degrees, J2000 equinox",
               "universal date of observation",
               "Title of observing program"
             ]

      assert rows == [
               [
                 "HI.19941118.65412.fits",
                 "HIRES Spectrograph",
                 nil,
                 15.84556,
                 70.26828,
                 "1994-11-18 00:00:00",
                 "Program Title Not Found"
               ],
               [
                 "HI.19941201.80171.fits",
                 "HIRES Spectrograph",
                 nil,
                 15.84556,
                 70.26828,
                 "1994-12-01 00:00:00",
                 "Program Title Not Found"
               ],
               [
                 "HI.19941201.80420.fits",
                 "HIRES Spectrograph",
                 nil,
                 15.84556,
                 70.26828,
                 "1994-12-01 00:00:00",
                 "Program Title Not Found"
               ],
               [
                 "HI.19941201.83588.fits",
                 "HIRES Spectrograph",
                 nil,
                 15.84556,
                 70.26828,
                 "1994-12-01 00:00:00",
                 "Program Title Not Found"
               ],
               [
                 "HI.19941210.06503.fits",
                 "HIRES Spectrograph",
                 nil,
                 344.0,
                 89.9,
                 "1994-12-10 00:00:00",
                 "Program Title Not Found"
               ]
             ]
    end
  end

  #####################
  # Private functions #
  #####################

  defp fixture(name, service \\ "gaia"), do: File.read!(Path.join([@fixtures, service, name]))

  # A successful result whose TABLE holds the given elements.
  defp result(table) do
    """
    <VOTABLE><RESOURCE type="results">
      <INFO name="QUERY_STATUS" value="OK"/>
      <TABLE>#{table}</TABLE>
    </RESOURCE></VOTABLE>
    """
  end
end
