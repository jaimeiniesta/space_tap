defmodule SpaceTAP.VOTable.ValueTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.Field
  alias SpaceTAP.VOTable.Value

  describe "parse_text/2" do
    test "reads an empty cell as nil, whatever the datatype (§5.1)" do
      for datatype <- [
            :boolean,
            :unsignedByte,
            :short,
            :int,
            :long,
            :char,
            :unicodeChar,
            :float,
            :double
          ] do
        assert parse("", datatype) == {:ok, nil}
      end
    end

    test "rejects bit and the complex datatypes, even in an empty cell" do
      assert parse("1", :bit) == {:error, ~s(field "col": the bit datatype is not supported)}

      for datatype <- [:bit, :floatComplex, :doubleComplex], text <- ["", "1 2"] do
        assert {:error, _} = parse(text, datatype, arraysize: "*")
      end
    end
  end

  describe "parse_text/2 with booleans" do
    test "reads T, t, 1 and true in any case as true (§6)" do
      for text <- ["T", "t", "1", "true", "TRUE", "tRUe", " T\n"] do
        assert parse(text, :boolean) == {:ok, true}, "expected #{inspect(text)} to be true"
      end
    end

    test "reads F, f, 0 and false in any case as false (§6)" do
      for text <- ["F", "f", "0", "false", "FalsE"] do
        assert parse(text, :boolean) == {:ok, false}, "expected #{inspect(text)} to be false"
      end
    end

    test "reads a question mark as nil (§6)" do
      assert parse("?", :boolean) == {:ok, nil}
    end

    test "rejects anything else" do
      assert parse("yes", :boolean) == {:error, ~s(field "col": "yes" is not a valid boolean)}

      for text <- ["2", "tru", "truee", "TF", "T F"] do
        assert {:error, _} = parse(text, :boolean), "expected #{inspect(text)} to be rejected"
      end
    end
  end

  describe "parse_text/2 with floats and doubles" do
    test "reads a sign, a positive decimal number and an exponent, each but the number optional (§6)" do
      assert parse("1.5", :double) == {:ok, 1.5}
      assert parse("-2", :double) == {:ok, -2.0}
      assert parse("+.5", :double) == {:ok, 0.5}
      assert parse("3.", :double) == {:ok, 3.0}
      assert parse("1e3", :double) == {:ok, 1.0e3}
      assert parse("6.02E+23", :double) == {:ok, 6.02e23}
      assert parse(" -1.5e-3\n", :double) == {:ok, -1.5e-3}
    end

    test "doesn't count the digits of the exponent" do
      assert parse("1e0003", :float) == {:ok, 1.0e3}
    end

    test "reads a float as the exact value of its 32 bits, the value BINARY2 would give (ADR 0007)" do
      assert parse("3.6157947", :float) == {:ok, 3.6157946586608887}
      assert parse("0.1", :float) == {:ok, 0.10000000149011612}
      assert parse("0.1", :double) == {:ok, 0.1}
    end

    test "reads NaN as nil and the infinities as atoms (ADR 0007)" do
      for datatype <- [:float, :double] do
        assert parse("NaN", datatype) == {:ok, nil}
        assert parse("+Inf", datatype) == {:ok, :infinity}
        assert parse("-Inf", datatype) == {:ok, :neg_infinity}
      end
    end

    test "rejects other spellings of the special values (§6)" do
      for text <- ["nan", "NAN", "Inf", "inf", "+inf", "-INF", "Infinity", "-Infinity"] do
        assert {:error, _} = parse(text, :double), "expected #{inspect(text)} to be rejected"
      end
    end

    test "rejects numbers out of the IEEE range, and takes those too small as zero (§6)" do
      assert parse("1e309", :double) == {:error, ~s(field "col": "1e309" is not a valid double)}
      assert {:error, _} = parse("3.5e38", :float)
      assert {:error, _} = parse("-3.5e38", :float)
      # The largest float is 0x7F7FFFFF in IEEE 754, which rounds 3.4028235e38 down.
      <<largest_float::float-32>> = <<0x7F7F_FFFF::32>>
      assert parse("3.4028235e38", :float) == {:ok, largest_float}
      assert parse("1e-400", :double) == {:ok, 0.0}
      assert parse("1e-46", :float) == {:ok, 0.0}
    end

    test "rejects text that isn't a decimal number" do
      for text <- [
            "abc",
            ".",
            "+",
            "-.e5",
            "1.5.2",
            "1e",
            "e3",
            "1e+",
            "1,5",
            "0x1F",
            "1 2",
            "--1",
            "1_000.0"
          ] do
        assert {:error, _} = parse(text, :double), "expected #{inspect(text)} to be rejected"
      end
    end
  end

  describe "parse_text/2 with strings" do
    test "keeps the white space, which matters in strings (§5.1)" do
      assert parse(" Apple ", :char, arraysize: "*") == {:ok, " Apple "}
      assert parse("a\n\tb", :unicodeChar, arraysize: "*") == {:ok, "a\n\tb"}
      assert parse(" ", :char, arraysize: "*") == {:ok, " "}
    end

    test "reads a field without arraysize as one character (§2.1)" do
      assert parse("A", :char) == {:ok, "A"}
      assert parse("Я", :unicodeChar) == {:ok, "Я"}
      assert parse("AB", :char) == {:error, ~s(field "col": "AB" is not a valid char)}
    end

    test "takes a string shorter than a fixed arraysize, like the Apple of §5.1" do
      assert parse("Apple", :char, arraysize: "10") == {:ok, "Apple"}
      assert parse("Orange", :char, arraysize: "6") == {:ok, "Orange"}

      assert parse("Orange", :char, arraysize: "5") ==
               {:error, ~s(field "col": "Orange" doesn't fit arraysize "5")}
    end

    test "takes a string up to the length of a variable arraysize (§2.2)" do
      assert parse("Apple", :char, arraysize: "5*") == {:ok, "Apple"}
      assert {:error, _} = parse("Orange", :char, arraysize: "5*")

      assert parse(String.duplicate("a", 1000), :char, arraysize: "*") ==
               {:ok, String.duplicate("a", 1000)}
    end

    test "counts the characters of a unicodeChar, not its bytes" do
      assert parse("Ярослав", :unicodeChar, arraysize: "7") == {:ok, "Ярослав"}
    end

    test "rejects a char that isn't ASCII, and takes it as a unicodeChar (§6)" do
      assert parse("Málaga", :char, arraysize: "*") ==
               {:error, ~s(field "col": "Málaga" is not a valid char)}

      assert parse("Málaga", :unicodeChar, arraysize: "*") == {:ok, "Málaga"}
    end
  end

  describe "parse_text/2 with arrays" do
    test "reads the numbers of an array, separated by any white space (§5.1)" do
      assert parse("1 2 4 8 16", :int, arraysize: "*") == {:ok, [1, 2, 4, 8, 16]}
      assert parse(" 23\n-11\t9 ", :int, arraysize: "*") == {:ok, [23, -11, 9]}
      assert parse("1.62 4.56 3.44", :double, arraysize: "3") == {:ok, [1.62, 4.56, 3.44]}
    end

    test "reads each element by its datatype" do
      assert parse("1 NaN +Inf -Inf", :double, arraysize: "*") ==
               {:ok, [1.0, nil, :infinity, :neg_infinity]}

      assert parse("T F ?", :boolean, arraysize: "3") == {:ok, [true, false, nil]}
      assert parse("0xFFFF 0x7FFF", :short, arraysize: "2") == {:ok, [-1, 32_767]}
    end

    test "rejects an array with an element that isn't of its datatype" do
      assert parse("1 x 3", :int, arraysize: "3") ==
               {:error, ~s(field "col": "x" is not a valid int)}
    end

    test "requires exactly as many elements as a fixed arraysize" do
      assert parse("1 2", :double, arraysize: "3") ==
               {:error, ~s(field "col": "1 2" doesn't fit arraysize "3")}

      assert {:error, _} = parse("1 2 3 4", :double, arraysize: "3")
    end

    test "takes up to as many elements as a variable arraysize (§2.2)" do
      assert parse("1 2 3", :int, arraysize: "100*") == {:ok, [1, 2, 3]}
      assert {:error, _} = parse("1 2 3", :int, arraysize: "2*")
    end

    test "reads an array with no elements as nil, since TABLEDATA writes it like a null (§5.5)" do
      assert parse(" \n ", :int, arraysize: "*") == {:ok, nil}
    end

    test "nests a multidimensional array, the first dimension changing fastest (§2.2)" do
      assert parse("1 2 3 4 5 6", :int, arraysize: "2x3") == {:ok, [[1, 2], [3, 4], [5, 6]]}
      assert parse("1 2 3 4", :int, arraysize: "2x*") == {:ok, [[1, 2], [3, 4]]}
      assert parse("1 2 3 4 5 6", :int, arraysize: "2x3*") == {:ok, [[1, 2], [3, 4], [5, 6]]}

      assert parse("1 2 3 4 5 6 7 8", :int, arraysize: "2x2x*") ==
               {:ok, [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]}
    end

    test "requires whole rows in a multidimensional array" do
      assert {:error, _} = parse("1 2 3", :int, arraysize: "2x*")
      assert {:error, _} = parse("1 2 3 4 5", :int, arraysize: "2x3")
      assert {:error, _} = parse("1 2 3 4 5 6 7 8", :int, arraysize: "2x3*")
    end

    test "reads a multidimensional array of characters as a list of strings (§2.2)" do
      assert parse("AppleOrangKiwi ", :char, arraysize: "5x3") ==
               {:ok, ["Apple", "Orang", "Kiwi "]}

      assert parse("AppleOrang", :char, arraysize: "5x*") == {:ok, ["Apple", "Orang"]}
      assert {:error, _} = parse("AppleKiwi", :char, arraysize: "5x*")
    end

    test "rejects an arraysize that §2.2 doesn't define" do
      assert parse("1", :int, arraysize: "3x") ==
               {:error, ~s(field "col": "3x" is not a valid arraysize)}

      for arraysize <- ["", "x", "x3", "*x3", "3**", "-1", "+1", "1.5", "0", "0*", "a"],
          datatype <- [:int, :char] do
        assert {:error, _} = parse("1", datatype, arraysize: arraysize),
               "expected #{inspect(arraysize)} to be rejected"
      end
    end
  end

  describe "parse_text/2 with the null value of the field" do
    test "reads the null value as nil, compared once both are read, since it follows the TABLEDATA rules (§4.7)" do
      assert parse("-32768", :short, null: "-32768") == {:ok, nil}
      assert parse("0x8000", :short, null: "-32768") == {:ok, nil}
      assert parse("-32768", :short, null: "0x8000") == {:ok, nil}
      assert parse("+7", :int, null: " 7 ") == {:ok, nil}
      assert parse("5", :short, null: "-32768") == {:ok, 5}
    end

    test "applies to each element of an array (§5.5)" do
      assert parse("1 -999 3", :int, arraysize: "3", null: "-999") == {:ok, [1, nil, 3]}
    end

    test "compares a string as a whole, white space included" do
      assert parse("N/A", :char, arraysize: "*", null: "N/A") == {:ok, nil}
      assert parse("N/A ", :char, arraysize: "*", null: "N/A") == {:ok, "N/A "}

      assert parse("AppleN/A  Kiwi ", :char, arraysize: "5x*", null: "N/A  ") ==
               {:ok, ["Apple", nil, "Kiwi "]}
    end

    test "rejects a null value that isn't one value of the datatype (§4.7)" do
      assert parse("5", :short, null: "abc") ==
               {:error, ~s(field "col": the null value "abc" is not a valid short)}

      assert {:error, _} = parse("5", :short, null: "1 2")
      assert {:error, _} = parse("5", :short, arraysize: "*", null: "1 2")
    end
  end

  describe "parse_text/2 with integers" do
    test "reads the decimal representation, with an optional sign (§6)" do
      assert parse("255", :unsignedByte) == {:ok, 255}
      assert parse("-32768", :short) == {:ok, -32_768}
      assert parse("+15", :short) == {:ok, 15}
      assert parse("2147483647", :int) == {:ok, 2_147_483_647}
      assert parse("-9223372036854775808", :long) == {:ok, -9_223_372_036_854_775_808}
    end

    test "ignores the whitespace around a number (§5.1)" do
      assert parse(" \t42\r\n", :int) == {:ok, 42}
    end

    test "rejects a number out of the datatype's range (§6)" do
      assert parse("32768", :short) == {:error, ~s(field "col": "32768" is not a valid short)}
      assert {:error, _} = parse("256", :unsignedByte)
      assert {:error, _} = parse("-1", :unsignedByte)
      assert {:error, _} = parse("2147483648", :int)
      assert {:error, _} = parse("9223372036854775808", :long)
    end

    test "reads the hexadecimal representation as the bits of the BINARY serialization" do
      assert parse("0xff", :unsignedByte) == {:ok, 255}
      assert parse("0x7FFF", :short) == {:ok, 32_767}
      assert parse("0xFFFF", :short) == {:ok, -1}
      assert parse("0x8000", :short) == {:ok, -32_768}
      assert parse("0xffffffff", :int) == {:ok, -1}
      assert parse("0x8000000000000000", :long) == {:ok, -9_223_372_036_854_775_808}
      assert parse("0x1", :long) == {:ok, 1}
    end

    test "rejects more hexadigits than the datatype holds (§6)" do
      assert {:error, _} = parse("0x100", :unsignedByte)
      assert {:error, _} = parse("0x0001F", :short)
      assert {:error, _} = parse("0x000000001", :int)
      assert {:error, _} = parse("0x00000000000000001", :long)
    end

    test "rejects text that isn't an integer" do
      for text <- ["1.5", "1e3", "abc", "1 2", "- 1", "0x", "0xg", "0X1F", "-0x1", "1_000"] do
        assert {:error, _} = parse(text, :int), "expected #{inspect(text)} to be rejected"
      end
    end
  end

  defp parse(text, datatype, attributes \\ []) do
    Value.parse_text(text, struct!(Field, [name: "col", datatype: datatype] ++ attributes))
  end
end
