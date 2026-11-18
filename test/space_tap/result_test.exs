defmodule SpaceTAP.ResultTest do
  use ExUnit.Case, async: true

  alias Explorer.DataFrame
  alias SpaceTAP.{Field, Result}

  describe "to_dataframe/1" do
    test "gives each column the type of its field" do
      df = Result.to_dataframe(scalars())

      assert DataFrame.dtypes(df) == %{
               "byte" => {:u, 8},
               "short" => {:s, 16},
               "int" => {:s, 32},
               "long" => {:s, 64},
               "float" => {:f, 32},
               "double" => {:f, 64},
               "flag" => :boolean,
               "letter" => :string,
               "name" => :string,
               "title" => :string
             }
    end

    test "keeps every value, null and infinity" do
      df = Result.to_dataframe(scalars())

      assert DataFrame.to_columns(df) == %{
               "byte" => [255, 0, nil],
               "short" => [-32_768, 32_767, nil],
               "int" => [-2_147_483_648, 2_147_483_647, nil],
               "long" => [-9_223_372_036_854_775_808, 9_223_372_036_854_775_807, nil],
               "float" => [3.6157946586608887, :infinity, nil],
               "double" => [0.1, :neg_infinity, nil],
               "flag" => [true, false, nil],
               "letter" => ["A", "B", nil],
               "name" => ["Maia", "Electra", nil],
               "title" => ["Ἀλκυόνη", "Ἠλέκτρα", nil]
             }
    end

    test "keeps the order of the columns" do
      result =
        votable([{"source_id", :long, nil}, {"ra", :double, nil}, {"dec", :double, nil}], [])

      assert DataFrame.names(Result.to_dataframe(result)) == ["source_id", "ra", "dec"]
    end

    test "gives an array a list type, nested once for each dimension but the string's" do
      result =
        votable(
          [
            {"magnitudes", :float, "3"},
            {"flags", :boolean, "*"},
            {"matrix", :short, "2x*"},
            {"bands", :char, "2x*"}
          ],
          [
            [[1.5, :infinity, nil], [true, false], [[1, 2], [3, 4], [5, 6]], ["BP", "RP"]],
            [nil, nil, nil, nil]
          ]
        )

      df = Result.to_dataframe(result)

      assert DataFrame.dtypes(df) == %{
               "magnitudes" => {:list, {:f, 32}},
               "flags" => {:list, :boolean},
               "matrix" => {:list, {:list, {:s, 16}}},
               "bands" => {:list, :string}
             }

      assert DataFrame.to_columns(df) == %{
               "magnitudes" => [[1.5, :infinity, nil], nil],
               "flags" => [[true, false], nil],
               "matrix" => [[[1, 2], [3, 4], [5, 6]], nil],
               "bands" => [["BP", "RP"], nil]
             }
    end

    test "gives a column of nulls the type of its field" do
      result = votable([{"parallax", :double, nil}], [[nil], [nil]])

      df = Result.to_dataframe(result)

      assert DataFrame.dtypes(df) == %{"parallax" => {:f, 64}}
      assert DataFrame.to_columns(df) == %{"parallax" => [nil, nil]}
    end

    test "keeps the columns and their types when there are no rows" do
      result = votable([{"source_id", :long, nil}, {"designation", :char, "*"}], [])

      df = Result.to_dataframe(result)

      assert DataFrame.n_rows(df) == 0
      assert DataFrame.names(df) == ["source_id", "designation"]
      assert DataFrame.dtypes(df) == %{"source_id" => {:s, 64}, "designation" => :string}
    end

    # The expected names are what astropy 8.0.2 gives for the same FIELDs
    # with use_names_over_ids=True, as PyVO's to_table() asks.
    test "renames a repeated column name as PyVO does" do
      for {names, renamed} <- [
            {["ra", "ra", "ra"], ["ra", "ra2", "ra3"]},
            {["ra", "ra", "ra2"], ["ra", "ra2", "ra22"]},
            {["a", "b", "a", "b"], ["a", "b", "a2", "b2"]}
          ] do
        result = votable(Enum.map(names, &{&1, :int, nil}), [])

        assert DataFrame.names(Result.to_dataframe(result)) == renamed
      end
    end

    test "keeps the values of a renamed column" do
      result = votable([{"ra", :double, nil}, {"ra", :double, nil}], [[56.75, 57.29]])

      assert DataFrame.to_columns(Result.to_dataframe(result)) == %{
               "ra" => [56.75],
               "ra2" => [57.29]
             }
    end

    test "gives every column of a CSV result the string type" do
      result = %Result{
        columns: ["source_id", "parallax"],
        rows: [["66529975427235712", "7.34"], ["65214031805717376", nil]],
        fields: nil,
        overflow: nil
      }

      df = Result.to_dataframe(result)

      assert DataFrame.dtypes(df) == %{"source_id" => :string, "parallax" => :string}

      assert DataFrame.to_columns(df) == %{
               "source_id" => ["66529975427235712", "65214031805717376"],
               "parallax" => ["7.34", nil]
             }
    end
  end

  # A VOTable result with one column of each datatype SpaceTAP reads.
  defp scalars do
    votable(
      [
        {"byte", :unsignedByte, nil},
        {"short", :short, nil},
        {"int", :int, nil},
        {"long", :long, nil},
        {"float", :float, nil},
        {"double", :double, nil},
        {"flag", :boolean, nil},
        {"letter", :char, nil},
        {"name", :char, "*"},
        {"title", :unicodeChar, "*"}
      ],
      [
        [
          255,
          -32_768,
          -2_147_483_648,
          -9_223_372_036_854_775_808,
          3.6157946586608887,
          0.1,
          true,
          "A",
          "Maia",
          "Ἀλκυόνη"
        ],
        [
          0,
          32_767,
          2_147_483_647,
          9_223_372_036_854_775_807,
          :infinity,
          :neg_infinity,
          false,
          "B",
          "Electra",
          "Ἠλέκτρα"
        ],
        List.duplicate(nil, 10)
      ]
    )
  end

  # A result as SpaceTAP reads it from a VOTable: the columns are the names of
  # the fields.
  defp votable(fields, rows) do
    fields =
      for {name, datatype, arraysize} <- fields,
          do: %Field{name: name, datatype: datatype, arraysize: arraysize}

    %Result{columns: Enum.map(fields, & &1.name), rows: rows, fields: fields, overflow: false}
  end
end
