defmodule SpaceTAP.VOTable.BinaryTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.Field
  alias SpaceTAP.VOTable.Binary

  @id %Field{name: "id", datatype: :int}
  @sptype %Field{name: "sptype", datatype: :char, arraysize: "*"}

  describe "rows/3 with BINARY" do
    test "reads the cells of each row one after another, with nothing between rows (§5.3)" do
      bytes = <<1::32, 2::32, "K3", 2::32, 0::32>>
      assert Binary.rows(bytes, [@id, @sptype], :binary) == {:ok, [[1, "K3"], [2, nil]]}
    end

    test "reads no bytes as no rows" do
      assert Binary.rows("", [@id, @sptype], :binary) == {:ok, []}
    end

    test "returns the error of the first cell it can't read" do
      assert Binary.rows(<<1::32, 3::32, "Ká">>, [@id, @sptype], :binary) ==
               {:error, ~s(field "sptype": "Ká" is not a valid char)}
    end

    test "rejects a row the bytes end in the middle of" do
      assert Binary.rows(<<1::32, 2::32, "K3", 2::32>>, [@id, @sptype], :binary) ==
               {:error, ~s(field "sptype": the data ends in the middle of the cell)}
    end

    test "reads the rows GAVO sent, as astropy 8.0.2 reads them" do
      # The STREAM GAVO sent on 9 November 2026 for SELECT TOP 3 hipno, ra,
      # dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 3.
      stream =
        "AAAAAT9N4Sb25M5LP/FsmTsk7yNBEZmaNYP7EwAAAAJGNQAAAAI/bxupfr73zcAzf7PPpcUhQRRR7DbMH28" <>
          "AAAADSzNWAAAAAz90gzdXhSITQENt/RYVwQdA04UfNVGHXwAAAAJCOQ=="

      fields = [
        %Field{name: "hipno", datatype: :int, null: "-2147483648"},
        %Field{name: "ra", datatype: :double},
        %Field{name: "dec", datatype: :double},
        %Field{name: "vmag", datatype: :float},
        %Field{name: "parallax", datatype: :float},
        %Field{name: "SpType", datatype: :char, arraysize: "*"}
      ]

      assert Binary.rows(Base.decode64!(stream), fields, :binary) ==
               {:ok,
                [
                  [1, 0.00091185, 1.08901332, 9.100000381469727, 9.833332796915784e-7, "F5"],
                  [2, 0.00379737, -19.49883745, 9.270000457763672, 6.083333119022427e-6, "K3V"],
                  [3, 0.00500795, 38.85928608, 6.610000133514404, 7.805555810591613e-7, "B9"]
                ]}
    end

    test "rejects bytes for a table without fields, which hold no row" do
      assert Binary.rows("", [], :binary) == {:ok, []}
      assert Binary.rows(<<0>>, [], :binary) == {:error, "the table has data but no fields"}
    end
  end

  describe "rows/3 with BINARY2" do
    test "starts each row with a null flag per field, the first field in the most significant bit (§5.4)" do
      bytes = <<0b0100_0000, 1::32, 0::32, 0b1000_0000, 0::32, 2::32, "K3">>
      assert Binary.rows(bytes, [@id, @sptype], :binary2) == {:ok, [[1, nil], [nil, "K3"]]}
    end

    test "skips a flagged cell without reading what it holds, which §5.4 only recommends" do
      flag = %Field{name: "flag", datatype: :boolean}
      bytes = <<0b1000_0000, ?x, 2::32, "K3">>
      assert Binary.rows(bytes, [flag, @sptype], :binary2) == {:ok, [[nil, "K3"]]}
    end

    test "takes a second flag byte for the ninth field, which §5.4 calls the eighth" do
      fields = for n <- 1..9, do: %Field{name: "c#{n}", datatype: :unsignedByte}
      bytes = <<0b0000_0001, 0b1000_0000, 1, 2, 3, 4, 5, 6, 7, 8, 9>>

      assert Binary.rows(bytes, fields, :binary2) == {:ok, [[1, 2, 3, 4, 5, 6, 7, nil, nil]]}
    end

    test "ignores the flag bits after the last field, which §5.4 says shall be 0" do
      bytes = <<0b0011_1111, 1::32, 2::32, "K3">>
      assert Binary.rows(bytes, [@id, @sptype], :binary2) == {:ok, [[1, "K3"]]}
    end

    test "still reads the null value of a cell that isn't flagged (§5.5)" do
      id = %{@id | null: "-1"}
      assert Binary.rows(<<0, -1::32, 0::32>>, [id, @sptype], :binary2) == {:ok, [[nil, nil]]}
    end

    test "rejects a row the bytes end in the middle of" do
      fields = for n <- 1..9, do: %Field{name: "c#{n}", datatype: :unsignedByte}

      assert Binary.rows(<<0>>, fields, :binary2) ==
               {:error, "the data ends in the middle of the null flags of a row"}

      assert Binary.rows(<<0, 1::32>>, [@id, @sptype], :binary2) ==
               {:error, ~s(field "sptype": the data ends in the middle of the cell)}
    end

    test "reads the rows Gaia sent, as astropy 8.0.2 reads them" do
      [stream] =
        Regex.run(~r/<STREAM encoding='base64'>([^<]*)</, File.read!("test/fixtures/gaia/ok.xml"),
          capture: :all_but_first
        )

      source_id = %Field{name: "source_id", datatype: :long}

      assert Binary.rows(Base.decode64!(stream, ignore: :whitespace), [source_id], :binary2) ==
               {:ok,
                [[137_332_953_680_255_488], [137_333_061_054_618_240], [137_339_035_353_986_048]]}
    end
  end
end
