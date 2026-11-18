defmodule SpaceTAP.ADQLTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.ADQL

  doctest ADQL

  describe "literal/1" do
    test "quotes a string and doubles the single quotes inside it" do
      for {value, literal} <- [
            {"Pleiades", "'Pleiades'"},
            {"Barnard's Star", "'Barnard''s Star'"},
            {"'quoted'", "'''quoted'''"},
            {"", "''"},
            {"Ἀλκυόνη", "'Ἀλκυόνη'"}
          ] do
        assert ADQL.literal(value) == literal
      end
    end

    test "writes an integer in decimal" do
      for {value, literal} <- [
            {42, "42"},
            {-7, "-7"},
            {66_529_975_427_235_712, "66529975427235712"}
          ] do
        assert ADQL.literal(value) == literal
      end
    end

    test "writes a float with an uppercase E before the exponent" do
      for {value, literal} <- [
            {56.75, "56.75"},
            {-24.12, "-24.12"},
            {1.0e-5, "1.0E-5"},
            {1.5e20, "1.5E20"}
          ] do
        assert ADQL.literal(value) == literal
      end
    end

    test "writes nil as NULL" do
      assert ADQL.literal(nil) == "NULL"
    end

    test "writes a list as the parenthesized literals of its values, for IN" do
      assert ADQL.literal(["WASP-39 b", "GJ 436 b"]) == "('WASP-39 b', 'GJ 436 b')"
      assert ADQL.literal([1, 2.5, nil]) == "(1, 2.5, NULL)"
    end

    test "raises for a value ADQL has no literal for" do
      for value <- [:infinity, :neg_infinity, true, false, :pleiades, %{}, {1, 2}] do
        assert_raise ArgumentError,
                     ~r/ADQL has no literal for #{Regex.escape(inspect(value))}/,
                     fn ->
                       ADQL.literal(value)
                     end
      end
    end

    test "raises for an empty list, which IN doesn't take" do
      assert_raise ArgumentError, ~r/empty list/, fn -> ADQL.literal([]) end
    end

    test "raises for a list inside a list" do
      assert_raise ArgumentError, ~r/ADQL has no literal for \[1, 2\]/, fn ->
        ADQL.literal([[1, 2], 3])
      end
    end
  end

  describe "cone/5" do
    test "writes a cone search with CONTAINS, POINT and CIRCLE in ICRS" do
      assert ADQL.cone("ra", "dec", 56.75, 24.12, 1.0) ==
               "CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1"
    end

    test "inserts the columns as given and writes the numbers as literals" do
      assert ADQL.cone("g.ra", "g.dec", 56, -24.5, 1.0e-6) ==
               "CONTAINS(POINT('ICRS', g.ra, g.dec), CIRCLE('ICRS', 56, -24.5, 1.0E-6)) = 1"
    end

    test "raises when the center or the radius isn't a number" do
      for args <- [
            ["ra", "dec", "56.75", 24.12, 1.0],
            ["ra", "dec", 56.75, nil, 1.0],
            ["ra", "dec", 56.75, 24.12, :infinity]
          ] do
        assert_raise ArgumentError, ~r/expected a number/, fn -> apply(ADQL, :cone, args) end
      end
    end

    test "raises when a column isn't a string" do
      assert_raise ArgumentError, ~r/expected the column as a string, got: :ra/, fn ->
        ADQL.cone(:ra, "dec", 56.75, 24.12, 1.0)
      end
    end
  end
end
