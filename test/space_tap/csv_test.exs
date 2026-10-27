defmodule SpaceTAP.CSVTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.{CSV, Result}

  @fixtures Path.expand("../fixtures/gaia", __DIR__)

  describe "parse/1" do
    test "reads Gaia's header as columns and every following line as a row" do
      assert {:ok, %Result{columns: columns, rows: rows}} = CSV.parse(fixture("pleiades.csv"))

      assert columns == ["source_id", "designation", "ra", "dec", "parallax", "phot_g_mean_mag"]
      assert length(rows) == 5
      assert Enum.all?(rows, &(length(&1) == 6 and nil not in &1))

      assert hd(rows) == [
               "66526127137440128",
               "Gaia DR3 66526127137440128",
               "57.29068893293528",
               "24.053211829998986",
               "8.118448445799721",
               "3.6157947"
             ]
    end

    test "reads the header as columns and turns Gaia's empty parallax into nil" do
      assert {:ok, %Result{columns: columns, rows: rows}} = CSV.parse(fixture("nulls.csv"))

      assert columns == ["source_id", "designation", "ra", "dec", "parallax"]
      assert length(rows) == 3

      assert hd(rows) == [
               "137349618154728320",
               "Gaia DR3 137349618154728320",
               "44.84873196549282",
               "35.39514769148478",
               nil
             ]
    end

    test "turns an empty cell in the middle of a row into nil" do
      assert {:ok, %Result{rows: [["1", nil, "3"]]}} = CSV.parse("a,b,c\n1,,3\n")
    end

    test "accepts CRLF line endings" do
      assert {:ok, %Result{columns: ["a", "b"], rows: [["1", "2"], ["3", "4"]]}} =
               CSV.parse("a,b\r\n1,2\r\n3,4\r\n")
    end

    test "keeps commas inside quoted values" do
      assert {:ok, %Result{rows: [["Pleiades, M45", "56.75"]]}} =
               CSV.parse("name,ra\r\n\"Pleiades, M45\",56.75\r\n")
    end

    test "returns columns and no rows for a header-only body, as MAXREC=0 gives" do
      assert {:ok, %Result{columns: ["source_id", "ra", "dec"], rows: []}} =
               CSV.parse(fixture("maxrec_0.csv"))
    end

    test "fails on an empty body, which has no header" do
      assert {:error, message} = CSV.parse("")
      assert message =~ "header"
    end

    test "fails when a row has a different number of fields than the header" do
      assert {:error, message} = CSV.parse("a,b\n1,2\n3,4,5\n")
      assert message =~ "data row 2 has 3 fields, expected 2"
    end

    test "fails on malformed CSV" do
      assert {:error, message} = CSV.parse("a,b\n\"unclosed,2\n")
      assert message =~ "invalid CSV"
    end
  end

  #####################
  # Private functions #
  #####################

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))
end
