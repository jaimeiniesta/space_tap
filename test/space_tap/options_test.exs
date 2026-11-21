defmodule SpaceTAP.OptionsTest do
  use ExUnit.Case, async: true

  alias SpaceTAP.Options

  describe "validate!/2" do
    test "fills in the default of each option that isn't given" do
      assert Enum.sort(Options.validate!([], [:format, :maxrec, :req_options, :timeout, :schema])) ==
               [format: :csv, maxrec: nil, req_options: [], schema: nil, timeout: :infinity]

      assert Enum.sort(Options.validate!([maxrec: 5], [:format, :maxrec])) ==
               [format: :csv, maxrec: 5]
    end

    test "raises for an option the function doesn't take, as Keyword.validate!/2 does" do
      assert_raise ArgumentError, ~r/unknown keys \[:timeout\]/, fn ->
        Options.validate!([timeout: 1000], [:format, :req_options])
      end
    end

    test "raises for a :format other than :csv or :votable" do
      for format <- [:fits, "votable", nil] do
        assert_raise ArgumentError,
                     "expected :format to be :csv or :votable, got: #{inspect(format)}",
                     fn -> Options.validate!([format: format], [:format]) end
      end
    end

    test "raises for a :maxrec that isn't a non-negative integer, and takes 0" do
      assert Options.validate!([maxrec: 0], [:maxrec]) == [maxrec: 0]

      for maxrec <- [-1, 1.5, "3"] do
        assert_raise ArgumentError, ~r/expected :maxrec to be a non-negative integer/, fn ->
          Options.validate!([maxrec: maxrec], [:maxrec])
        end
      end
    end

    test "raises for a :req_options that isn't a keyword list" do
      for req_options <- [%{}, :nope, [1]] do
        assert_raise ArgumentError, ~r/expected :req_options to be a keyword list/, fn ->
          Options.validate!([req_options: req_options], [:req_options])
        end
      end
    end

    test "raises for a :timeout that isn't a non-negative integer or :infinity" do
      assert Options.validate!([timeout: 0], [:timeout]) == [timeout: 0]

      for timeout <- [-1, 1.5, "1000", nil] do
        assert_raise ArgumentError,
                     ~r/expected :timeout to be a non-negative integer or :infinity/,
                     fn -> Options.validate!([timeout: timeout], [:timeout]) end
      end
    end

    test "raises for a :schema that isn't a string" do
      assert Options.validate!([schema: "gaiadr3"], [:schema]) == [schema: "gaiadr3"]

      assert_raise ArgumentError, ~r/expected :schema to be a string, got: :hipparcos/, fn ->
        Options.validate!([schema: :hipparcos], [:schema])
      end
    end
  end
end
