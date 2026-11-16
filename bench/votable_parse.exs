# Times SpaceTAP.VOTable.parse/1 on 100,000 rows of Gaia DR3, the same rows
# in TABLEDATA and in BINARY2, to measure changes to the VOTable reader. Each
# time is the median of five runs, each in a fresh process.
#
#     mix run bench/votable_parse.exs [--save]
#
# --save writes what parse/1 gives for each file next to it. A run without it
# checks that parse/1 still gives exactly that (===), so a change that makes
# reading faster can be shown to change no value, not even an integer into a
# float.
#
# The first run downloads the files into bench/data/, which git ignores, from
# the copy of Gaia DR3 at ARI Heidelberg, which offers both serializations.
# bench/xmerl_vs_saxy.exs downloaded the same files for ADR 0008.

alias SpaceTAP.VOTable

defmodule Download do
  # One synchronous query per file (TAP 1.1 §2.1). The service names its
  # serializations in its capabilities: votable/b2 for BINARY2 and votable/td
  # for TABLEDATA. ORDER BY makes both files hold the same rows, and MAXREC
  # asks for all of them (DALI 1.1 §3.4.4).
  @service "https://gaia.ari.uni-heidelberg.de/tap"

  @query """
  SELECT TOP 100000 source_id, ra, dec, parallax, phot_g_mean_mag, bp_rp
  FROM gaiadr3.gaia_source
  ORDER BY source_id
  """

  def fetch(path, format) do
    if not File.exists?(path) do
      IO.puts("Downloading #{Path.basename(path)} from ARI Heidelberg (FORMAT=#{format})...")

      response =
        Req.post!("#{@service}/sync",
          form: [REQUEST: "doQuery", LANG: "ADQL", FORMAT: format, MAXREC: 100_000, QUERY: @query],
          decode_body: false,
          receive_timeout: 120_000,
          retry: false
        )

      # A service may stop at its row limit with an OVERFLOW status, or write
      # the rows it has followed by an ERROR (DALI 1.1 §4.4), so a 200 alone
      # isn't enough.
      case VOTable.parse(response.body) do
        {:ok, %{overflow: false, rows: rows}} when length(rows) == 100_000 -> :ok
        other -> raise "the service didn't give the 100,000 rows: #{inspect(other, limit: 5)}"
      end

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, response.body)
    end
  end
end

defmodule Bench do
  @runs 5

  def run(path, save?) do
    xml = File.read!(path)
    saved = Path.rootname(path) <> ".etf"

    if save? do
      File.write!(saved, :erlang.term_to_binary(VOTable.parse(xml)))
    end

    same = check(xml, saved)
    times = for _run <- 1..@runs, do: time(xml)
    median = times |> Enum.sort() |> Enum.at(div(@runs, 2))

    IO.puts(
      "#{Path.basename(path)}: #{format(median)} median of #{@runs} " <>
        "(#{Enum.map_join(times, ", ", &format/1)}), #{same}"
    )
  end

  defp check(xml, saved) do
    case File.read(saved) do
      {:ok, binary} ->
        if VOTable.parse(xml) === :erlang.binary_to_term(binary),
          do: "same result as the saved one",
          else: "DIFFERENT RESULT from the saved one"

      {:error, :enoent} ->
        "no saved result to compare with: run with --save"
    end
  end

  # The process gets the document as a reference to the same binary, and
  # sends back only the time, not the table.
  defp time(xml) do
    task =
      Task.async(fn ->
        {micros, {:ok, _table}} = :timer.tc(fn -> VOTable.parse(xml) end)
        micros
      end)

    Task.await(task, :infinity)
  end

  defp format(micros), do: "#{Float.round(micros / 1000, 1)} ms"
end

save? = "--save" in System.argv()
data = Path.expand("data", __DIR__)

for {file, format} <- [{"tabledata.xml", "votable/td"}, {"binary2.xml", "votable/b2"}] do
  path = Path.join(data, file)
  Download.fetch(path, format)
  Bench.run(path, save?)
end
