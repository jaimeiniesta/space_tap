defmodule SpaceTAP.Test.Pyvo do
  @moduledoc false

  # Runs a query through PyVO, an Astropy-affiliated Python client for IVOA
  # services, and compares its result with SpaceTAP's. pyvo_query.py, next to
  # this file, is a PEP 723 script that pins PyVO and prints JSON; `uv run`
  # installs what it needs. Without `uv`, parity tests skip locally and fail
  # when CI is set.
  #
  # PyVO reads the VOTable the service sends by default. A parity test asks
  # SpaceTAP for the same VOTable with `format: :votable` and compares the
  # columns, the values of every row and overflow. Rows are compared sorted,
  # since without ORDER BY their order may be arbitrary (ADQL 2.1 §2.2). The
  # script follows ADR 0007 where SpaceTAP differs from astropy: an empty
  # string or array is null. JSON has no infinities, so the script writes them
  # as "Infinity" and "-Infinity", and SpaceTAP's :infinity and :neg_infinity
  # are compared as those strings.
  #
  # The test also asks SpaceTAP for CSV and checks that its header names the
  # same columns as the VOTable fields PyVO reads, and that it has as many
  # rows. Pass `csv: false` for a service that doesn't send CSV.
  #
  # The parity tests on the fixtures need no service: PyVO reads each file,
  # SpaceTAP's VOTable reader reads the same bytes, and they compare the same
  # way, the rows in the order of the file. Job documents are compared the
  # same way, by what SpaceTAP reads from them: the phase, the message of the
  # error summary and the result, and so are VOSI documents: the
  # availability URL of capabilities and the fields of an availability.
  #
  # The metadata of a service is compared too: its tables by name, the
  # columns of one table by name, unit and UCD, and its availability. PyVO
  # reads tables and columns from the VOSI /tables resource, and SpaceTAP
  # from TAP_SCHEMA, so the test also checks that the two agree.

  import ExUnit.Assertions

  alias Explorer.{DataFrame, Series}
  alias SpaceTAP.{Result, UWS, VOSI, VOTable}

  @runner Path.expand("pyvo_query.py", __DIR__)

  # For `@moduletag skip:` in the parity tests.
  @spec skip_reason() :: String.t() | nil
  def skip_reason do
    if is_nil(System.find_executable("uv")) and is_nil(System.get_env("CI")) do
      "`uv` is required to run the PyVO parity tests"
    end
  end

  # Besides `:csv` and `:async`, `opts` go to SpaceTAP.query/3, or to
  # SpaceTAP.async_query/3 with `async: true`, which runs the query as a job
  # in both clients; PyVO gets `:maxrec` only.
  @spec assert_parity(String.t(), String.t(), keyword()) :: true
  def assert_parity(service_url, adql, opts \\ []) do
    {csv?, opts} = Keyword.pop(opts, :csv, true)
    {async?, opts} = Keyword.pop(opts, :async, false)
    query = if async?, do: &SpaceTAP.async_query/3, else: &SpaceTAP.query/3
    mode = if async?, do: ["--async"], else: []

    assert %{"columns" => pyvo_columns, "rows" => pyvo_rows, "overflow" => pyvo_overflow} =
             run(mode ++ [service_url, adql] ++ maxrec_arg(opts))

    if csv? do
      assert {:ok, %Result{columns: columns, rows: rows}} = query.(service_url, adql, opts)

      assert columns == pyvo_columns
      assert length(rows) == length(pyvo_rows)
    end

    assert {:ok, %Result{columns: columns, rows: rows, overflow: overflow}} =
             query.(service_url, adql, Keyword.put(opts, :format, :votable))

    assert columns == pyvo_columns
    assert overflow == pyvo_overflow
    assert Enum.sort(Enum.map(rows, &as_json/1)) === Enum.sort(pyvo_rows)
  end

  # Reads VOTable files with PyVO, all in one run of the script. Gives what
  # PyVO read from each path, or the error it gave.
  @spec read_files([Path.t()]) :: %{Path.t() => map()}
  def read_files(paths), do: run(["--files" | paths])

  # Compares what SpaceTAP reads from a VOTable file with what PyVO read
  # from it. A file both refuse, such as an error document, passes. The data
  # frame of the result has the names and the types of the columns of PyVO's
  # to_table().
  @spec assert_file_parity(Path.t(), map()) :: true
  def assert_file_parity(path, pyvo) do
    case {VOTable.parse(File.read!(path)), pyvo} do
      {{:ok, table},
       %{"columns" => columns, "rows" => rows, "overflow" => overflow} = %{
         "names" => names,
         "dtypes" => dtypes
       }} ->
        assert Enum.map(table.fields, & &1.name) == columns
        assert table.overflow == overflow
        assert Enum.map(table.rows, &as_json/1) === rows

        df =
          Result.to_dataframe(%Result{
            columns: columns,
            rows: table.rows,
            fields: table.fields,
            overflow: table.overflow
          })

        assert DataFrame.names(df) == names
        assert Enum.map(DataFrame.names(df), &numpy_dtype(df[&1])) == dtypes

      {{:ok, _table}, %{"error" => error}} ->
        flunk("SpaceTAP reads #{path} and PyVO doesn't: #{error}")

      {{_refused, _message}, %{"error" => _pyvo_error}} ->
        true

      {{_refused, message}, _pyvo} ->
        flunk("PyVO reads #{path} and SpaceTAP doesn't: #{message}")
    end
  end

  # Compares the tables, the columns of `table` and the availability of a
  # service with what PyVO gives. PyVO reads tables and columns from the
  # VOSI /tables resource, and SpaceTAP from TAP_SCHEMA, so the test checks
  # that both describe the same tables, by name, and the same columns, by
  # name, unit and UCD, in any order. `tables: false` leaves the tables out,
  # for a service whose TAP_SCHEMA.tables SpaceTAP can't read, such as Gaia's,
  # which PyVO lists from /tables.
  @spec assert_metadata_parity(String.t(), String.t(), keyword()) :: true
  def assert_metadata_parity(service_url, table, opts \\ []) do
    {compare_tables?, opts} = Keyword.pop(opts, :tables, true)

    assert %{
             "tables" => pyvo_tables,
             "columns" => pyvo_columns,
             "availability" => pyvo_availability
           } =
             run(["--metadata", service_url, table])

    if compare_tables? do
      assert {:ok, tables} = SpaceTAP.tables(service_url, opts)
      assert tables |> Enum.map(& &1.name) |> Enum.sort() == Enum.sort(pyvo_tables)
    end

    assert {:ok, columns} = SpaceTAP.columns(service_url, table, opts)

    assert columns |> Enum.map(&[&1.name, &1.unit, &1.ucd]) |> Enum.sort() ==
             Enum.sort(pyvo_columns)

    assert {:ok, availability} = SpaceTAP.availability(service_url, opts)
    assert availability_as_json(availability) == pyvo_availability
  end

  # Reads VOSI capabilities and availability documents with PyVO, all in
  # one run of the script.
  @spec read_vosi_files([Path.t()]) :: %{Path.t() => map()}
  def read_vosi_files(paths), do: run(["--vosi" | paths])

  # Compares what SpaceTAP reads from a VOSI document with what PyVO read:
  # the availability URL of capabilities, and the fields of an availability.
  @spec assert_vosi_parity(Path.t(), map()) :: true
  def assert_vosi_parity(path, %{"availability_url" => url}) do
    assert VOSI.availability_url(File.read!(path)) == {:ok, url}
  end

  def assert_vosi_parity(path, %{"availability" => pyvo}) do
    assert {:ok, availability} = VOSI.availability(File.read!(path))
    assert availability_as_json(availability) == pyvo
  end

  # Reads job documents with PyVO, all in one run of the script.
  @spec read_jobs([Path.t()]) :: %{Path.t() => map()}
  def read_jobs(paths), do: run(["--jobs" | paths])

  # Compares what SpaceTAP reads from a job document with what PyVO read
  # from it. PyVO lists every result named result, where SpaceTAP refuses a
  # document with more than one.
  @spec assert_job_parity(Path.t(), map()) :: true
  def assert_job_parity(path, pyvo) do
    case {UWS.parse(File.read!(path)), pyvo} do
      {{:ok, job}, %{"phase" => phase, "error_summary" => message, "results" => results}} ->
        assert job.phase |> Atom.to_string() |> String.upcase() == phase
        assert job.error_summary == message
        assert List.wrap(job.result) == results

      {{:ok, _job}, %{"error" => error}} ->
        flunk("SpaceTAP reads #{path} and PyVO doesn't: #{error}")

      {{:error, _message}, %{"error" => _pyvo_error}} ->
        true

      {{:error, message}, _pyvo} ->
        flunk("PyVO reads #{path} and SpaceTAP doesn't: #{message}")
    end
  end

  #####################
  # Private functions #
  #####################

  defp run(args) do
    uv = System.find_executable("uv") || flunk("`uv` is required to run the PyVO parity tests")

    case System.cmd(uv, ["run", "--quiet", @runner | args]) do
      {output, 0} ->
        assert {:ok, result} = JSON.decode(output)
        result

      {output, status} ->
        flunk("PyVO runner exited with status #{status}: #{String.trim(output)}")
    end
  end

  # The NumPy dtype astropy gives a column of the same values, as
  # pyvo_query.py writes it: "string" for text and "list" for an array.
  defp numpy_dtype(series) do
    case Series.dtype(series) do
      {:u, bits} -> "uint#{bits}"
      {:s, bits} -> "int#{bits}"
      {:f, bits} -> "float#{bits}"
      :boolean -> "bool"
      :string -> "string"
      {:list, _dtype} -> "list"
    end
  end

  defp availability_as_json(availability) do
    %{
      "available" => availability.available,
      "up_since" => availability.up_since,
      "down_at" => availability.down_at,
      "back_at" => availability.back_at,
      "notes" => availability.notes
    }
  end

  defp as_json(:infinity), do: "Infinity"
  defp as_json(:neg_infinity), do: "-Infinity"
  defp as_json(values) when is_list(values), do: Enum.map(values, &as_json/1)
  defp as_json(value), do: value

  defp maxrec_arg(opts) do
    case Keyword.fetch(opts, :maxrec) do
      {:ok, maxrec} -> [Integer.to_string(maxrec)]
      :error -> []
    end
  end
end
