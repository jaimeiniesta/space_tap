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
  # error summary and the result.

  import ExUnit.Assertions

  alias SpaceTAP.{Result, UWS, VOTable}

  @runner Path.expand("pyvo_query.py", __DIR__)

  # For `@moduletag skip:` in the parity tests.
  @spec skip_reason() :: String.t() | nil
  def skip_reason do
    if is_nil(System.find_executable("uv")) and is_nil(System.get_env("CI")) do
      "`uv` is required to run the PyVO parity tests"
    end
  end

  # Besides `:csv`, `opts` go to SpaceTAP.query/3; PyVO gets `:maxrec` only.
  @spec assert_parity(String.t(), String.t(), keyword()) :: true
  def assert_parity(service_url, adql, opts \\ []) do
    {csv?, opts} = Keyword.pop(opts, :csv, true)

    assert %{"columns" => pyvo_columns, "rows" => pyvo_rows, "overflow" => pyvo_overflow} =
             query(service_url, adql, opts)

    if csv? do
      assert {:ok, %Result{columns: columns, rows: rows}} =
               SpaceTAP.query(service_url, adql, opts)

      assert columns == pyvo_columns
      assert length(rows) == length(pyvo_rows)
    end

    assert {:ok, %Result{columns: columns, rows: rows, overflow: overflow}} =
             SpaceTAP.query(service_url, adql, Keyword.put(opts, :format, :votable))

    assert columns == pyvo_columns
    assert overflow == pyvo_overflow
    assert Enum.sort(Enum.map(rows, &as_json/1)) === Enum.sort(pyvo_rows)
  end

  # Reads VOTable files with PyVO, all in one run of the script. Gives what
  # PyVO read from each path, or the error it gave.
  @spec read_files([Path.t()]) :: %{Path.t() => map()}
  def read_files(paths), do: run(["--files" | paths])

  # Compares what SpaceTAP reads from a VOTable file with what PyVO read
  # from it. A file both refuse, such as an error document, passes.
  @spec assert_file_parity(Path.t(), map()) :: true
  def assert_file_parity(path, pyvo) do
    case {VOTable.parse(File.read!(path)), pyvo} do
      {{:ok, table}, %{"columns" => columns, "rows" => rows, "overflow" => overflow}} ->
        assert Enum.map(table.fields, & &1.name) == columns
        assert table.overflow == overflow
        assert Enum.map(table.rows, &as_json/1) === rows

      {{:ok, _table}, %{"error" => error}} ->
        flunk("SpaceTAP reads #{path} and PyVO doesn't: #{error}")

      {{_refused, _message}, %{"error" => _pyvo_error}} ->
        true

      {{_refused, message}, _pyvo} ->
        flunk("PyVO reads #{path} and SpaceTAP doesn't: #{message}")
    end
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

  defp query(service_url, adql, opts), do: run([service_url, adql] ++ maxrec_arg(opts))

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
