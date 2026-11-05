# Compares :xmerl_sax_parser with Saxy on a large Gaia result, to decide which
# one reads VOTable documents. The criterion was fixed before measuring: Saxy
# replaces xmerl only if it halves the parse time or the peak memory on either
# file. The peak counts everything the reading process holds at once, its heap
# and the binaries it refers to, the document included. Times and peaks are
# the median of several runs, each in a fresh process.
#
#     elixir bench/xmerl_vs_saxy.exs
#
# The first run downloads the two files into bench/data/, which git ignores:
# the same 100,000 rows of Gaia DR3 in BINARY2, the serialization the ESA Gaia
# archive sends by default, and in TABLEDATA. They come from the copy of Gaia
# DR3 at ARI Heidelberg, which offers both serializations, because the ESA
# archive was too overloaded to answer when the benchmark first ran, on
# 5 November 2026.

Mix.install([{:saxy, "1.7.0"}])

for file <- ~w(field.ex votable.ex votable/value.ex) do
  Code.require_file("../lib/space_tap/#{file}", __DIR__)
end

defmodule Download do
  # One synchronous query per file (TAP 1.1 §2.1): a single POST, with no job
  # to poll or delete. The service names its serializations in its
  # capabilities: votable/b2 for BINARY2 and votable/td for TABLEDATA.

  @service "https://gaia.ari.uni-heidelberg.de/tap"

  # ORDER BY makes both files hold the same rows.
  @query """
  SELECT TOP 100000 source_id, ra, dec, parallax, phot_g_mean_mag, bp_rp
  FROM gaiadr3.gaia_source
  ORDER BY source_id
  """

  def fetch(path, format) do
    if not File.exists?(path) do
      IO.puts("Downloading #{Path.basename(path)} from ARI Heidelberg (FORMAT=#{format})...")
      {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])
      xml = query!(format)

      # A service may write the rows it has when it runs out of time, followed
      # by an ERROR status (DALI 1.1 §4.4), or stop at its row limit with an
      # OVERFLOW status (§4.4.1), so a 200 alone isn't enough.
      case SpaceTAP.VOTable.query_status(xml) do
        {:ok, {"OK", _message}} -> :ok
        other -> raise "the service didn't finish the query: #{inspect(other)}"
      end

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, xml)
    end
  end

  # A service may apply a default row limit below the TOP of the query, so
  # MAXREC asks for all of it (DALI 1.1 §3.4.4). A failed request stops the
  # script: there is no retry.
  defp query!(format) do
    body =
      URI.encode_query(%{
        "REQUEST" => "doQuery",
        "LANG" => "ADQL",
        "FORMAT" => format,
        "MAXREC" => "100000",
        "QUERY" => @query
      })

    request = {~c"#{@service}/sync", [], ~c"application/x-www-form-urlencoded", body}

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    case :httpc.request(:post, request, [ssl: ssl, timeout: 120_000], body_format: :binary) do
      {:ok, {{_version, 200, _reason}, _headers, xml}} -> xml
      other -> raise "the query failed: #{inspect(other, printable_limit: 500)}"
    end
  end
end

defmodule Collector do
  # What SpaceTAP.VOTable needs from a document: the attributes of each FIELD,
  # with the null of its VALUES (VOTable 1.5 §4.7), the text of every TD, row by
  # row, and the text of the STREAM. Both parsers make the same calls, with text
  # as binaries, so the benchmark compares the parsers and what it takes to get
  # binaries out of them.

  def new, do: %{fields: [], in_field: false, rows: [], row: [], text: nil, stream: nil}

  def start(:field, attributes, state) do
    %{state | fields: [Map.new(attributes) | state.fields], in_field: true}
  end

  def start(:values, attributes, %{in_field: true, fields: [field | fields]} = state) do
    case List.keyfind(attributes, "null", 0) do
      {_name, null} -> %{state | fields: [Map.put(field, "null", null) | fields]}
      nil -> state
    end
  end

  def start(tag, _attributes, state) when tag in [:td, :stream], do: %{state | text: []}
  def start(_tag, _attributes, state), do: state

  def collecting?(state), do: state.text != nil

  def text(_chunk, %{text: nil} = state), do: state
  def text(chunk, state), do: %{state | text: [state.text | chunk]}

  def stop(:field, state), do: %{state | in_field: false}

  def stop(:td, state) do
    %{state | row: [IO.iodata_to_binary(state.text) | state.row], text: nil}
  end

  def stop(:tr, state), do: %{state | rows: [Enum.reverse(state.row) | state.rows], row: []}
  def stop(:stream, state), do: %{state | stream: IO.iodata_to_binary(state.text), text: nil}
  def stop(_tag, state), do: state

  def result(state) do
    %{fields: Enum.reverse(state.fields), rows: Enum.reverse(state.rows), stream: state.stream}
  end
end

defmodule XmerlParser do
  # With the options SpaceTAP.VOTable uses. xmerl gives names and text as
  # charlists, one list cell per character, so the handler matches names as
  # charlists and turns into binaries only the text it keeps.

  def parse(xml) do
    options = [
      :disallow_entities,
      :skip_external_dtd,
      event_fun: &event/3,
      event_state: Collector.new()
    ]

    {:ok, state, _rest} = :xmerl_sax_parser.stream(xml, options)
    Collector.result(state)
  end

  defp event({:startElement, _uri, name, _qname, attributes}, _location, state) do
    tag = tag(name)
    Collector.start(tag, attributes(tag, attributes), state)
  end

  defp event({:endElement, _uri, name, _qname}, _location, state) do
    Collector.stop(tag(name), state)
  end

  defp event({:characters, chars}, _location, state) do
    if Collector.collecting?(state), do: Collector.text(List.to_string(chars), state), else: state
  end

  defp event(_event, _location, state), do: state

  defp attributes(tag, attributes) when tag in [:field, :values] do
    for {_uri, _prefix, name, value} <- attributes,
        do: {List.to_string(name), List.to_string(value)}
  end

  defp attributes(_tag, _attributes), do: []

  defp tag(~c"FIELD"), do: :field
  defp tag(~c"VALUES"), do: :values
  defp tag(~c"TR"), do: :tr
  defp tag(~c"TD"), do: :td
  defp tag(~c"STREAM"), do: :stream
  defp tag(_name), do: :other
end

defmodule SaxyParser do
  # Saxy gives names and text as binaries that point into the document, and
  # leaves any namespace prefix on the names.

  @behaviour Saxy.Handler

  def parse(xml) do
    {:ok, state} = Saxy.parse_string(xml, __MODULE__, Collector.new())
    Collector.result(state)
  end

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attributes}, state) do
    {:ok, Collector.start(tag(name), attributes, state)}
  end

  def handle_event(:end_element, name, state), do: {:ok, Collector.stop(tag(name), state)}
  def handle_event(:characters, chars, state), do: {:ok, Collector.text(chars, state)}
  def handle_event(_event, _data, state), do: {:ok, state}

  defp tag("FIELD"), do: :field
  defp tag("VALUES"), do: :values
  defp tag("TR"), do: :tr
  defp tag("TD"), do: :td
  defp tag("STREAM"), do: :stream

  defp tag(name) do
    case :binary.split(name, ":") do
      [_prefix, local] -> tag(local)
      [_name] -> :other
    end
  end
end

defmodule Peak do
  # The most memory a fresh process held at once while running fun, in bytes,
  # read at the start of each garbage collection and at the end. It counts the
  # heap and the binaries the process refers to, which live outside it when
  # they are over 64 bytes. The document is one of them: SpaceTAP reads it in
  # the caller's process, with the response body already in memory, so it is
  # part of what a read costs.

  def bytes(fun) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        receive do
          :go -> :ok
        end

        result = fun.()
        [memory: memory, binary: binaries] = Process.info(self(), [:memory, :binary])
        off_heap = binaries |> Enum.uniq_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        send(parent, {:final, self(), memory + off_heap, map_size(result)})
      end)

    1 = :erlang.trace(pid, true, [:garbage_collection, {:tracer, self()}])
    send(pid, :go)
    collect(pid, monitor, 0)
  end

  defp collect(pid, monitor, peak) do
    receive do
      {:trace, ^pid, event, info} when event in [:gc_minor_start, :gc_major_start] ->
        collect(pid, monitor, max(peak, heap(info)))

      {:trace, ^pid, _event, _info} ->
        collect(pid, monitor, peak)

      {:final, ^pid, bytes, _size} ->
        collect(pid, monitor, max(peak, bytes))

      {:DOWN, ^monitor, :process, ^pid, :normal} ->
        peak

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        exit(reason)
    end
  end

  # Sizes come in words. bin_vheap_size and bin_old_vheap_size are the
  # binaries outside the heap that the young and old heaps refer to. The
  # wordsize key is what the process asked for when the collection started,
  # not the size of a word.
  defp heap(info) do
    heap = info[:heap_block_size] + info[:old_heap_block_size] + info[:mbuf_size]
    off_heap = info[:bin_vheap_size] + info[:bin_old_vheap_size]
    (heap + off_heap) * :erlang.system_info(:wordsize)
  end
end

defmodule Clock do
  # The time fun takes in a fresh process, in nanoseconds. A fresh process
  # starts with a small heap and no garbage from earlier runs, as a caller of
  # SpaceTAP.query/3 would. Benchee measured 19 s for Saxy on TABLEDATA where a
  # fresh process takes about 2.5 s with the same handler, and the cause wasn't
  # found, so times are taken here, the way Peak takes the memory.

  def nanoseconds(fun) do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        start = System.monotonic_time(:nanosecond)
        fun.()
        send(parent, {:elapsed, self(), System.monotonic_time(:nanosecond) - start})
      end)

    receive do
      {:elapsed, ^pid, nanoseconds} ->
        Process.demonitor(monitor, [:flush])
        nanoseconds

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        exit(reason)
    end
  end
end

defmodule Runs do
  # Takes a measure an odd number of times, prints every run and returns the
  # median.
  def median(label, count, measure, format) do
    runs = for _run <- 1..count, do: measure.()
    median = runs |> Enum.sort() |> Enum.at(div(count, 2))
    IO.puts("  #{label}: #{format.(median)} (runs: #{Enum.map_join(runs, ", ", format)})")
    median
  end
end

defmodule Report do
  def ms(nanoseconds), do: "#{Float.round(nanoseconds / 1_000_000, 1)} ms"
  def mb(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"
end

data = Path.join(__DIR__, "data")

documents =
  for {serialization, format, file} <- [
        {"BINARY2", "votable/b2", "binary2.xml"},
        {"TABLEDATA", "votable/td", "tabledata.xml"}
      ],
      into: %{} do
    path = Path.join(data, file)
    Download.fetch(path, format)
    {serialization, File.read!(path)}
  end

parsers = %{"xmerl" => &XmerlParser.parse/1, "Saxy" => &SaxyParser.parse/1}

# This check also loads the code of both parsers before anything is timed.
IO.puts("\nBoth parsers read the same thing:")

for {serialization, xml} <- documents do
  result = XmerlParser.parse(xml)
  ^result = SaxyParser.parse(xml)

  IO.puts(
    "  #{serialization}: #{Report.mb(byte_size(xml))}, #{length(result.fields)} fields, " <>
      "#{length(result.rows)} TABLEDATA rows, a STREAM of #{byte_size(result.stream || "")} bytes"
  )
end

IO.puts("\nTime, the median of five runs in a fresh process:")

times =
  for {serialization, xml} <- documents, {parser, parse} <- parsers, into: %{} do
    measure = fn -> Clock.nanoseconds(fn -> parse.(xml) end) end

    {{serialization, parser},
     Runs.median("#{serialization}, #{parser}", 5, measure, &Report.ms/1)}
  end

IO.puts("\nPeak memory, the median of three runs in a fresh process:")

peaks =
  for {serialization, xml} <- documents, {parser, parse} <- parsers, into: %{} do
    measure = fn -> Peak.bytes(fn -> parse.(xml) end) end

    {{serialization, parser},
     Runs.median("#{serialization}, #{parser}", 3, measure, &Report.mb/1)}
  end

# The cells are parsed the same way whichever parser reads the XML. Their cost
# says how much of the whole read the choice of parser can change.
%{fields: attributes, rows: rows} = XmerlParser.parse(documents["TABLEDATA"])

# SpaceTAP.Field is loaded while the script runs, after it is compiled, so its
# struct can only be built with struct!/2.
fields =
  Enum.map(attributes, fn field ->
    struct!(SpaceTAP.Field,
      name: field["name"],
      datatype: String.to_existing_atom(field["datatype"]),
      arraysize: field["arraysize"],
      null: field["null"]
    )
  end)

parse_cells = fn ->
  Enum.map(
    rows,
    &Enum.zip_with(&1, fields, fn text, field ->
      SpaceTAP.VOTable.Value.parse_text(text, field)
    end)
  )
end

true = parse_cells.() |> List.flatten() |> Enum.all?(&match?({:ok, _value}, &1))

IO.puts("\nparse_text, the median of five runs in a fresh process:")

# The rows are copied into each fresh process when it is spawned, before the
# clock starts.
cells_time =
  Runs.median(
    "every TABLEDATA cell",
    5,
    fn -> Clock.nanoseconds(parse_cells) end,
    &Report.ms/1
  )

IO.puts("""

Criterion: Saxy replaces xmerl if xmerl/Saxy is 2 or more for the time or the
peak memory of either file.

| File      | Measure     | xmerl      | Saxy       | xmerl/Saxy |
|-----------|-------------|------------|------------|------------|\
""")

comparisons =
  for {serialization, _xml} <- documents,
      {measure, values, format} <- [
        {"median time", times, &Report.ms/1},
        {"peak memory", peaks, &Report.mb/1}
      ] do
    xmerl = values[{serialization, "xmerl"}]
    saxy = values[{serialization, "Saxy"}]
    ratio = xmerl / saxy

    IO.puts(
      "| #{String.pad_trailing(serialization, 9)} | #{measure} | #{String.pad_leading(format.(xmerl), 10)} " <>
        "| #{String.pad_leading(format.(saxy), 10)} | #{String.pad_leading(to_string(Float.round(ratio, 2)), 10)} |"
    )

    # The criterion is applied to the exact ratio: 1.996 rounds to 2.0 but
    # doesn't halve anything.
    ratio
  end

tabledata = fn parser -> times[{"TABLEDATA", parser}] end

IO.puts("""

parse_text on the #{length(rows) * length(fields)} TABLEDATA cells: #{Report.ms(cells_time)}, \
#{round(100 * cells_time / (tabledata.("xmerl") + cells_time))}% of reading the file with xmerl \
and #{round(100 * cells_time / (tabledata.("Saxy") + cells_time))}% with Saxy.
""")

if Enum.any?(comparisons, &(&1 >= 2)) do
  IO.puts("Saxy halves the time or the peak memory on at least one file: it replaces xmerl.")
else
  IO.puts("Saxy halves neither the time nor the peak memory on either file: xmerl stays.")
end
