defmodule SpaceTAPTAPSchemaTest do
  # SpaceTAP.tables/2 and SpaceTAP.columns/3, which read TAP_SCHEMA with a
  # sync query. The fixtures are what each service answered to the query
  # its README gives.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias SpaceTAP.{Column, Error, Table}

  @service_url "https://tap.example.org/tap"
  @req_options [plug: {Req.Test, SpaceTAP}]
  @fixtures Path.expand("fixtures", __DIR__)

  describe "tables/2" do
    test "asks TAP_SCHEMA.tables for every table, as VOTable, at the sync endpoint" do
      stub_service(fixture("gavo", "tap_schema_tables.xml"))

      assert {:ok, _tables} = tables()
      assert_received {:request, conn, params}

      assert conn.method == "POST"
      assert conn.request_path == "/tap/sync"

      assert params == %{
               "REQUEST" => "doQuery",
               "LANG" => "ADQL",
               "FORMAT" => "votable",
               "QUERY" => "SELECT * FROM TAP_SCHEMA.tables"
             }
    end

    test "asks for the tables of one schema with :schema, written as a literal" do
      stub_service(fixture("gavo", "tap_schema_tables.xml"))

      for {schema, where} <- [
            {"hipparcos", "schema_name = 'hipparcos'"},
            {"o'neil", "schema_name = 'o''neil'"}
          ] do
        assert {:ok, _tables} = tables(schema: schema)
        assert_received {:request, _conn, %{"QUERY" => query}}
        assert query == "SELECT * FROM TAP_SCHEMA.tables WHERE " <> where
      end
    end

    test "sends :maxrec as MAXREC" do
      stub_service(fixture("gavo", "tap_schema_tables.xml"))

      assert {:ok, _tables} = tables(maxrec: 5000)
      assert_received {:request, _conn, %{"MAXREC" => "5000"}}
    end

    test "reads each table from its row" do
      stub_service(fixture("gavo", "tap_schema_tables.xml"))

      assert tables() ==
               {:ok,
                [
                  %Table{
                    schema: "hipparcos",
                    name: "hipparcos.main",
                    type: "table",
                    description:
                      "The main result catalog from the ESA Hipparcos satellite, obtained\nNovember 1989 through March 1993. In the GAVO DC, several columns were\nleft out and all angles are given in degrees.",
                    utype: nil
                  }
                ]}
    end

    test "reads the columns by name, whatever their order and the extra ones the service adds" do
      stub_service(fixture("irsa", "tap_schema_tables.xml"))

      assert {:ok, [first | _tables]} = tables()

      assert first == %Table{
               schema: "2mass",
               name: "fp_psc",
               type: "table",
               description: "2MASS All-Sky Point Source Catalog (PSC)",
               utype: nil
             }
    end

    test "sorts the tables by table_index" do
      stub_service(fixture("exoplanet_archive", "tap_schema_tables.xml"))

      assert {:ok, tables} = tables()
      assert tables |> Enum.take(3) |> Enum.map(& &1.name) == ["DI_STARS_EXEP", "ps", "spectra"]
    end

    test "puts the tables without a table_index last, in the order they came" do
      stub_service(
        votable([{"table_name", "char"}, {"table_index", "int"}], [
          ["b", nil],
          ["c", "2"],
          ["a", nil],
          ["d", "1"]
        ])
      )

      assert {:ok, tables} = tables()
      assert Enum.map(tables, & &1.name) == ["d", "c", "b", "a"]
    end

    # ADQL names are case insensitive (ADQL 2.1 §2.1.7).
    test "reads the columns whatever the case of their names" do
      stub_service(votable([{"SCHEMA_NAME", "char"}, {"Table_Name", "char"}], [["h", "h.main"]]))

      assert {:ok, [%Table{schema: "h", name: "h.main"}]} = tables()
    end

    test "gives nil for the standard columns a service doesn't have" do
      stub_service(votable([{"table_name", "char"}], [["hipparcos.main"]]))

      assert tables() ==
               {:ok,
                [
                  %Table{
                    schema: nil,
                    name: "hipparcos.main",
                    type: nil,
                    description: nil,
                    utype: nil
                  }
                ]}
    end

    test "is a :decode_error when the result has no table_name column" do
      stub_service(fixture("gaia", "ok.xml"))

      assert {:error, %Error{type: :decode_error, message: message, status: 200}} = tables()
      assert message =~ "TAP_SCHEMA.tables has no table_name column"
    end

    # MAST marks every result as overflow, so the list comes back with a
    # warning rather than an error.
    test "returns the tables of a result marked as overflow, and warns that the list may be cut" do
      stub_service(fixture("mast", "tap_schema_tables.xml"))

      log =
        capture_log(fn ->
          assert {:ok, [%Table{name: "ivoa.obscore"}]} = tables()
        end)

      assert log =~ "[warning]"
      assert log =~ "marked TAP_SCHEMA.tables as overflow, so the list of tables may be cut short"
    end

    test "doesn't warn when the result isn't marked as overflow" do
      stub_service(fixture("gavo", "tap_schema_tables.xml"))

      assert capture_log(fn -> assert {:ok, [_table]} = tables() end) == ""
    end

    test "returns the error of the query" do
      stub_service(500, fixture("gavo", "syntax_error.xml"))

      assert {:error, %Error{type: :service_error, status: 500}} = tables()
    end

    test "raises for an unknown option and for a :schema that isn't a string" do
      assert_raise ArgumentError, ~r/unknown keys \[:format\]/, fn ->
        SpaceTAP.tables(@service_url, format: :csv)
      end

      assert_raise ArgumentError, ~r/expected :schema to be a string, got: :hipparcos/, fn ->
        SpaceTAP.tables(@service_url, schema: :hipparcos)
      end
    end
  end

  describe "columns/3" do
    test "asks TAP_SCHEMA.columns for the columns of the table, as VOTable" do
      stub_service(fixture("gavo", "tap_schema_columns.xml"))

      assert {:ok, _columns} = columns("hipparcos.main")
      assert_received {:request, conn, params}

      assert conn.request_path == "/tap/sync"

      assert params == %{
               "REQUEST" => "doQuery",
               "LANG" => "ADQL",
               "FORMAT" => "votable",
               "QUERY" => "SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'hipparcos.main'"
             }
    end

    test "writes the table name as a literal" do
      stub_service(fixture("gavo", "tap_schema_columns.xml"))

      assert {:ok, _columns} = columns(~s("I/239/hip_main"))
      assert_received {:request, _conn, %{"QUERY" => query}}
      assert query == ~s(SELECT * FROM TAP_SCHEMA.columns WHERE table_name = '"I/239/hip_main"')
    end

    test "reads each column from its row, with its flags as booleans" do
      stub_service(fixture("gavo", "tap_schema_columns.xml"))

      assert {:ok, [first | _columns]} = columns("hipparcos.main")

      assert first == %Column{
               name: "hipno",
               datatype: "int",
               arraysize: nil,
               xtype: nil,
               unit: nil,
               ucd: "meta.id;meta.main",
               utype: nil,
               description: "Identifier (HIP number)",
               indexed: true,
               principal: true,
               std: false
             }
    end

    # NED's TAP_SCHEMA follows TAP 1.0: no arraysize or xtype, ADQL types
    # in datatype, and no value in std.
    test "sorts the columns by column_index, and gives nil for what a TAP 1.0 service lacks" do
      stub_service(fixture("ned", "tap_schema_columns.xml"))

      assert {:ok, [first | _columns]} = columns("NEDTAP.objdir")

      assert first == %Column{
               name: "prefname",
               datatype: "CHAR",
               arraysize: nil,
               xtype: nil,
               unit: nil,
               ucd: "meta.id.cross",
               utype: nil,
               description: "preferred object name",
               indexed: true,
               principal: false,
               std: nil
             }
    end

    # IRSA declares arraysize as an int.
    test "writes an arraysize the service gives as an integer as a string" do
      stub_service(fixture("irsa", "tap_schema_columns.xml"))

      assert {:ok, [%Column{name: "ra", arraysize: "1"} | _columns]} = columns("fp_psc")
    end

    test "returns the columns of a result marked as overflow, and warns that the list may be cut" do
      stub_service(fixture("mast", "tap_schema_columns.xml"))

      log =
        capture_log(fn ->
          assert {:ok, columns} = columns("ivoa.obscore")
          assert length(columns) == 31
        end)

      assert log =~
               "marked TAP_SCHEMA.columns as overflow, so the list of columns may be cut short"
    end

    test "is an empty list for a table the service doesn't have" do
      stub_service(votable([{"table_name", "char"}, {"column_name", "char"}], []))

      assert columns("no_such_table") == {:ok, []}
    end

    test "is a :decode_error when a flag isn't 0 or 1" do
      stub_service(votable([{"column_name", "char"}, {"indexed", "int"}], [["ra", "2"]]))

      assert {:error, %Error{type: :decode_error, message: message}} = columns("t")
      assert message =~ "TAP_SCHEMA.columns: expected indexed to be 0 or 1, got: 2"
    end

    test "is a :decode_error when the result has no column_name column" do
      stub_service(fixture("gaia", "ok.xml"))

      assert {:error, %Error{type: :decode_error, message: message}} = columns("t")
      assert message =~ "TAP_SCHEMA.columns has no column_name column"
    end

    test "raises for an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:maxrec\]/, fn ->
        SpaceTAP.columns(@service_url, "t", maxrec: 10)
      end
    end
  end

  #####################
  # Private functions #
  #####################

  defp tables(opts \\ []), do: SpaceTAP.tables(@service_url, [req_options: @req_options] ++ opts)

  defp columns(table_name),
    do: SpaceTAP.columns(@service_url, table_name, req_options: @req_options)

  defp fixture(service, name), do: File.read!(Path.join([@fixtures, service, name]))

  # A VOTable result in TABLEDATA, with a char field of any length for each
  # "char" and the text of each cell, nil for an empty one.
  defp votable(fields, rows) do
    fields =
      Enum.map_join(fields, fn
        {name, "char"} -> ~s(<FIELD name="#{name}" datatype="char" arraysize="*"/>)
        {name, datatype} -> ~s(<FIELD name="#{name}" datatype="#{datatype}"/>)
      end)

    rows =
      Enum.map_join(rows, fn row ->
        "<TR>" <> Enum.map_join(row, &"<TD>#{&1}</TD>") <> "</TR>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <VOTABLE version="1.4" xmlns="http://www.ivoa.net/xml/VOTable/v1.3">
    <RESOURCE type="results">
    <INFO name="QUERY_STATUS" value="OK"/>
    <TABLE>#{fields}<DATA><TABLEDATA>#{rows}</TABLEDATA></DATA></TABLE>
    </RESOURCE>
    </VOTABLE>
    """
  end

  # Stands in for the TAP service: sends the request it gets to the test
  # process, with the form parameters decoded, and answers with a VOTable.
  defp stub_service(status \\ 200, body) do
    test = self()

    Req.Test.stub(SpaceTAP, fn conn ->
      {:ok, form, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn, URI.decode_query(form)})

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/x-votable+xml")
      |> Plug.Conn.send_resp(status, body)
    end)
  end
end
