<p align="center">
  <img src="https://raw.githubusercontent.com/jaimeiniesta/space_tap/main/assets/space_tap_logo.png" alt="SpaceTAP: an Elixir client for the IVOA Table Access Protocol" width="400">
</p>

# SpaceTAP

Query astronomical archives from Elixir.

SpaceTAP is a client for the IVOA [Table Access Protocol][tap] (TAP). ESA's
[Gaia archive][gaia] and the European Southern Observatory (ESO), among others,
publish their tables through it: you send a query in [ADQL][adql], a dialect of
SQL with functions for positions on the sky, and get the table back as Elixir
data.

## When to use it

- You want data from an archive in an Elixir app, a script or a Livebook: the
  stars of the Pleiades from ESA's Gaia catalogue, or the observations in the
  ESO archive.
- You would use [PyVO][pyvo] in Python and want to stay in Elixir. The
  [parity livebook](https://github.com/jaimeiniesta/space_tap/blob/main/livebooks/pyvo_parity.livemd)
  runs the same queries through both.

TAP returns tables. Images and spectra come through other IVOA protocols,
which SpaceTAP doesn't speak.

## Getting started

Add `space_tap` to the dependencies in `mix.exs`:

```elixir
{:space_tap, "~> 0.4.0"}
```

In Livebook or a script, use `Mix.install([{:space_tap, "~> 0.4.0"}])`.

`SpaceTAP.query/3` takes the URL of a TAP service and a query. This one asks
the GAVO Data Center, the German Virtual Observatory's archive, for the five
brightest stars within one degree of the centre of the Pleiades, from its copy
of ESA's Gaia DR3 catalogue:

```elixir
adql = """
SELECT TOP 5 source_id, ra, dec, parallax, phot_g_mean_mag
FROM gaia.dr3lite
WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1
  AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL
ORDER BY phot_g_mean_mag
"""

{:ok, result} = SpaceTAP.query("https://dc.g-vo.org/tap", adql)

result.columns
#=> ["source_id", "ra", "dec", "parallax", "phot_g_mean_mag"]

hd(result.rows)
#=> ["66526127137440128", "57.29068893293528", "24.053211829998986",
#=>  "8.118448", "3.6157947"]
```

The values are strings because SpaceTAP asks for CSV by default. Pass
`format: :votable` to get numbers, and each column's unit and type in
`result.fields`:

```elixir
{:ok, result} = SpaceTAP.query("https://dc.g-vo.org/tap", adql, format: :votable)

hd(result.rows)
#=> [66526127137440128, 57.29068893293528, 24.053211829998986,
#=>  8.118448257446289, 3.6157946586608887]
```

Each row is a list in the order of `columns`. To work with maps instead:

```elixir
Enum.map(result.rows, fn row -> Map.new(Enum.zip(result.columns, row)) end)
```

What to read next:

| To | Use |
|---|---|
| Run a query too slow for one request | `SpaceTAP.async_query/3` |
| Work with a data frame | `SpaceTAP.Result.to_dataframe/1` |
| List a service's tables and columns | `SpaceTAP.tables/2` and `SpaceTAP.columns/3` |
| Write values and cone searches as ADQL | `SpaceTAP.ADQL` |
| Ask a service whether it is up | `SpaceTAP.availability/2` |

The [getting started livebook](https://github.com/jaimeiniesta/space_tap/blob/main/livebooks/getting_started.livemd)
starts from this same query.

## Options

- `:format` is the format to ask the service for: `:csv`, the default, or
  `:votable`. See [CSV or VOTable](#csv-or-votable).
- `:maxrec` asks the service to return at most that many rows. The service may
  apply a lower limit of its own. `maxrec: 0` asks for the columns with no rows,
  although GAVO sends one row anyway.
- `:req_options` are passed to [Req][req], the HTTP client. Req waits 15 seconds
  for a response by default; for slower queries, raise it:

  ```elixir
  SpaceTAP.query(service_url, adql, req_options: [receive_timeout: 60_000])
  ```

  SpaceTAP sends each request once. Req would retry a `GET` that fails with a
  5xx or a timeout three times, waiting as long as a `Retry-After` header
  says, which can hold `availability/2` for minutes at a service in
  maintenance; to have that, pass `retry: :safe_transient`, Req's default.

  SpaceTAP sets the TAP request itself, but some Req options, such as
  `:headers`, can still change it. See `SpaceTAP.query/3`.

## Errors

A failed query returns `{:error, %SpaceTAP.Error{}}`, whose `:type` says what
went wrong:

| Type | When |
|---|---|
| `:service_error` | The service rejected the query, for example because of invalid ADQL or an unknown table. `:message` is the service's own message. |
| `:http_error` | An HTTP error status without an error document from the service, such as a proxy's 502 page. |
| `:transport_error` | No response arrived: the connection failed or timed out. |
| `:decode_error` | A successful response that can't be read as a result, such as malformed CSV. |
| `:timeout` | An [async query](#async-queries)'s job hadn't stopped when its `:timeout` ran out. |

Later versions may add types, so when you match on `:type`, keep a clause for
the rest.

`:status` holds the HTTP status, and `Exception.message/1` starts with it:

```elixir
{:error, error} =
  SpaceTAP.query(service_url, "SELECT TOP 3 source_id FROM gaia.no_such_table")

error.type
#=> :service_error

Exception.message(error)
#=> "(HTTP 500) Field query: Could not locate table 'gaia.no_such_table'"
```

## CSV or VOTable

SpaceTAP asks the service for CSV by default, as it did in 0.1. CSV is simple,
but it carries less than VOTable, the IVOA format for tables:

- **Every value is a string.** CSV has no types, so `"8.118448"`
  stays a string until you convert it, with `Float.parse/1` for example.
- **An empty cell is `nil`.** No IVOA standard says how CSV represents NULL.
  Gaia sends an empty field, and SpaceTAP can't tell it from an empty string.
- **A truncated result looks complete.** When a result reaches `:maxrec` or the
  service's own limit, the service cuts it short. A VOTable says so; CSV
  doesn't. If you get exactly as many rows as the limit, assume there are more.
  Gaia stops at 50,000 rows.
- **The service must support CSV.** TAP recommends CSV output but only requires
  VOTable. A service that answers in another format gives a `:decode_error`.
  CSV labelled `text/plain` instead of `text/csv` is read as CSV: the NASA
  Exoplanet Archive and KOA send it that way.

With `format: :votable`, SpaceTAP asks for VOTable instead:

```elixir
{:ok, result} = SpaceTAP.query("https://dc.g-vo.org/tap", adql, format: :votable)

hd(result.rows)
#=> [66526127137440128, 57.29068893293528, 24.053211829998986,
#=>  8.118448257446289, 3.6157946586608887]

result.overflow
#=> false
```

- **Each value has the type its column declares:** an integer, a float, a
  boolean, a string, or a list for an array. A null cell is `nil`, and so is a
  float holding NaN; +Inf and -Inf are `:infinity` and `:neg_infinity`.
- **`fields` describes each column** with a `SpaceTAP.Field`: its datatype,
  unit, UCD and description, among others.

  ```elixir
  Enum.at(result.fields, 4)
  #=> %SpaceTAP.Field{name: "phot_g_mean_mag", datatype: :float, unit: "mag", ...}
  ```

- **`overflow` is `true` when the service cut the result short,** at `:maxrec`
  or at a limit of its own (DALI 1.1 §4.4.1). MAST marks every result so (see
  [Compatibility](#compatibility)).

`parallax` and `phot_g_mean_mag` are `float`s, 32-bit numbers, and SpaceTAP
gives the exact value of their 32 bits as an Elixir float: `3.6157946586608887`,
where the CSV says `3.6157947`. Both are the same number, and PyVO reads the
same value.

The service picks how the rows travel inside the VOTable, and SpaceTAP reads
the three serializations TAP services send: TABLEDATA, BINARY and BINARY2. A
VOTable that comes when CSV was asked for, as MAST sends, is a `:decode_error`
that says to pass `format: :votable`, so the value types don't depend on the
service.

## Async queries

A sync query's result comes in the response to a single HTTP request, so the
query has to finish while that request is open. `SpaceTAP.async_query/3` runs
the query as a job instead (TAP 1.1 §2.2): the service keeps the job, with its
phase and its result, and SpaceTAP asks about it until it stops, reads the
result and deletes the job. It takes the options of `query/3` and returns the
same result:

```elixir
{:ok, result} =
  SpaceTAP.async_query("https://dc.g-vo.org/tap", adql,
    format: :votable,
    timeout: :timer.minutes(10)
  )

hd(result.rows)
#=> [66526127137440128, 57.29068893293528, 24.053211829998986,
#=>  8.118448257446289, 3.6157946586608887]
```

- **`:timeout` is how long to wait,** in milliseconds, or `:infinity`, the
  default. Services limit how long a job runs, from 60 seconds at the Gaia
  archive, ESO and NED to 3 days at IRSA, but not how long it waits in their
  queue. When the time runs out, SpaceTAP deletes the job, which stops it, and
  returns a `:timeout` error.
- **A job that fails is a `:service_error`** with the service's message:

  ```elixir
  {:error, error} =
    SpaceTAP.async_query(service_url, "SELECT TOP 3 source_id FROM gaia.no_such_table")

  error.message
  #=> "the job is ERROR: Field query: Could not locate table 'gaia.no_such_table'"
  ```

  The Gaia archive stops the job of an anonymous user after 60 seconds, which
  gives a `:service_error` for a job that is ABORTED.
- **SpaceTAP waits in your process,** with nothing to start or supervise. Each
  request asks the service to answer when the phase of the job changes, or
  after 30 seconds (UWS 1.1 §2.2.1.2), and SpaceTAP pauses between requests to
  a service that answers straight away instead.

### Following a job

`SpaceTAP.Job` has each step of `async_query/3`. Use them to keep a job, to
follow it from another process, or to come back for its result later:

```elixir
{:ok, job} = SpaceTAP.Job.submit("https://dc.g-vo.org/tap", adql, format: :votable)

job.url
#=> "https://dc.g-vo.org/__system__/tap/run/async/tisdf9q8"

{:ok, job} = SpaceTAP.Job.wait(job, timeout: :timer.minutes(10))

job.phase
#=> :completed

{:ok, result} = SpaceTAP.Job.result(job)
```

The job's URL is all SpaceTAP keeps: `SpaceTAP.Job.get(url, format: :votable)`
reads the job again, from any process. `wait/2` leaves the job on the service
when its `:timeout` runs out, so you can wait again, and a job stays there until
you delete it with `SpaceTAP.Job.delete/2` or the service destroys it. The NASA
Exoplanet Archive, KOA and IRSA answer that a job is deleted and keep it.

## Data frames

`SpaceTAP.Result.to_dataframe/1` turns a result into an
[Explorer][explorer] data frame, which stores each column as an array of one
type, as NumPy does, and filters, sorts and aggregates them in Rust. SpaceTAP
doesn't install Explorer, so add `{:explorer, "~> 0.13"}` to your dependencies.
In Livebook, [Kino Explorer][kino_explorer] shows the data frame as a table you
can sort and filter:

```elixir
{:ok, result} = SpaceTAP.query("https://dc.g-vo.org/tap", adql, format: :votable)
df = SpaceTAP.Result.to_dataframe(result)
#=> #Explorer.DataFrame<
#=>   Polars[5 x 5]
#=>   source_id s64 [66526127137440128, 65271996684817280, ...]
#=>   ra f64 [57.29068893293528, 56.2190045645284, ...]
#=>   dec f64 [24.053211829998986, 24.11313304360812, ...]
#=>   parallax f32 [8.118448257446289, 8.345685005187988, ...]
#=>   phot_g_mean_mag f32 [3.6157946586608887, 3.6982085704803467, ...]
#=> >

Explorer.Series.mean(df["parallax"])
#=> 8.149383354187012
```

- **Each column has the type of its field,** at the same width: a `float` is
  `{:f, 32}`, a `short` `{:s, 16}`, and an array a list. A null is a null of the
  series, which Explorer's functions skip.
- **A CSV result gives strings,** since CSV has no types: ask for VOTable to get
  numbers.
- **A repeated column name gets a number,** as PyVO names it: `SELECT a.ra,
  b.ra` gives `ra` and `ra2`. Seven of the nine services that answered on
  18 November 2026 send two columns with the same name, which a data frame
  can't hold.
- **Units and descriptions stay in `result.fields`,** since Explorer has no
  place for them.

A data frame keeps each column as one array outside the BEAM heap, where each
float of a row is a value of its own. The conversion starts from the rows,
though, so a large result still needs their memory while it is read.

## Tables and columns

Every TAP service describes its tables and their columns in `TAP_SCHEMA`.
`SpaceTAP.tables/2` lists the tables, and `SpaceTAP.columns/3` the columns of
one:

```elixir
{:ok, tables} = SpaceTAP.tables("https://dc.g-vo.org/tap", schema: "gaia")

Enum.map(tables, & &1.name)
#=> ["gaia.dr2light", "gaia.dr2epochflux", "gaia.dr2_ts_ssa", "gaia.dr3lite",
#=>  "gaia.edr3lite"]

{:ok, columns} = SpaceTAP.columns("https://dc.g-vo.org/tap", "gaia.dr3lite")

Enum.find(columns, &(&1.name == "ra"))
#=> %SpaceTAP.Column{name: "ra", datatype: "double", unit: "deg",
#=>   ucd: "pos.eq.ra;meta.main", indexed: true, principal: true, ...}
```

- **They come in the order the service recommends,** with `table_index` and
  `column_index` (TAP 1.1 §4).
- **What a service doesn't give is `nil`.** NED's `TAP_SCHEMA` follows TAP 1.0,
  with no `arraysize` or `xtype`, and an ADQL type such as `BIGINT` as
  `datatype`.
- **Without `:schema`, `tables/2` lists every table.** A service with thousands
  may cut the list short at its own limit; when it marks the list as overflow,
  the list comes with a warning in the log. MAST marks every result so.

## Writing ADQL

ADQL has no bound parameters: a value goes into a query as text. `SpaceTAP.ADQL`
writes values and cone searches as ADQL, and nothing more:

```elixir
alias SpaceTAP.ADQL

ADQL.literal("Barnard's Star")
#=> "'Barnard''s Star'"

ADQL.literal(["WASP-39 b", "GJ 436 b"])
#=> "('WASP-39 b', 'GJ 436 b')"

ADQL.cone("ra", "dec", 56.75, 24.12, 1.0)
#=> "CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1"
```

- **`literal/1` takes strings, numbers, `nil` and lists for `IN`,** doubles the
  single quotes of a string and writes a float's exponent with an uppercase
  `E`. ADQL has no literal for an infinity or a boolean, so those raise.
- **`cone/5` writes `CONTAINS`, `POINT` and `CIRCLE`, with `'ICRS'`,** which
  services with ADQL 2.0 and with ADQL 2.1 both take. ADQL 2.1 prefers
  `DISTANCE`, but the NASA Exoplanet Archive, KOA, CADC and MAST don't declare
  it.
- **The column names of `cone/5` go in as given,** so they must never come from
  user input.

## Availability

`SpaceTAP.availability/2` asks a service whether it is accepting requests:

```elixir
SpaceTAP.availability("https://dc.g-vo.org/tap")
#=> {:ok, %SpaceTAP.Availability{available: true,
#=>   up_since: "2026-10-30T12:22:56Z", down_at: nil, back_at: nil, notes: []}}
```

The service lists where its availability is in its capabilities: GAVO's is
outside the service URL, over `http://`, which SpaceTAP reads with `https://`.
It is what the service says about itself, so `available: false` comes only from
a service that answers with its availability document. A service that is down
usually gives an error instead. On 18 November 2026, VizieR didn't answer, a
`:transport_error`; SIMBAD sent a 404 page, an `:http_error`; and the Gaia
archive, closed for maintenance, sent a web page with HTTP 200 for every URL, a
`:decode_error`. A service that says it is available may still fail a query, so
to know whether queries work, run a small one.

## Compatibility

SpaceTAP follows [TAP 1.1][tap] and works with TAP 1.0 services. It is checked
against these:

| Service | Sync | Async | Tables | Availability |
|---|---|---|---|---|
| [Gaia archive (ESA)](#gaia-archive-esa) | CSV, VOTable | CSV, VOTable | `columns/3` only | Yes |
| [GAVO Data Center](#gavo-data-center) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [ESO](#eso) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [VizieR (CDS)](#vizier-and-simbad-cds) | CSV; VOTable not checked yet | Not checked yet | Not checked yet | Not checked yet |
| [SIMBAD (CDS)](#vizier-and-simbad-cds) | CSV; VOTable not checked yet | Not checked yet | Not checked yet | Not checked yet |
| [CADC](#cadc) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [NASA Exoplanet Archive](#nasa-exoplanet-archive) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [IRSA (IPAC)](#irsa-ipac) | CSV, VOTable | VOTable only | Yes | Yes |
| [NED (IPAC)](#ned-ipac) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [KOA (Keck)](#koa-keck) | CSV, VOTable | CSV, VOTable | Yes | Yes |
| [MAST](#mast) | VOTable only | CSV, VOTable | Yes, with a warning | Yes |

Sync queries were last checked on 16 November 2026 (Gaia on 13 November, IRSA
on 10 November), async queries on 17 November, and tables and availability on
18 November (Gaia on 21 November). Services change, so one that worked then may
behave differently today.

Each service is checked by services and parity tests, which query it live (see
[Development](#development)), and by fixtures, its responses captured for the
unit tests. GAVO also has the integration tests. The
[tour of TAP services](https://github.com/jaimeiniesta/space_tap/blob/main/livebooks/tap_services_tour.livemd)
livebook queries all of them.

The service URL of each one, and what it does differently:

### Gaia archive (ESA)

`https://gea.esac.esa.int/tap-server/tap`

- Gaia DR3 is in `gaiadr3.gaia_source`, and the query of
  [Getting started](#getting-started) runs on it too.
- Redirects `http://` to `https://`, which loses the query: use `https://`.
- Stops an async job of an anonymous user after 60 seconds, as `:aborted`.
- `tables/2` fails. Some table descriptions in its `TAP_SCHEMA` have a byte
  that isn't ASCII, which VOTable doesn't allow in a `char`, so the list is a
  `:decode_error`. With `:schema`, Gaia answers HTTP 500, as it does to any
  `WHERE` on `TAP_SCHEMA.tables`.

### GAVO Data Center

`https://dc.g-vo.org/tap`

- Runs DaCHS.
- Holds a copy of Gaia DR3 in `gaia.dr3lite`.
- Sends error documents with HTTP 500.
- Sends one row more than `:maxrec` asks for, and one row with `maxrec: 0`,
  marked as overflow.
- Lists its availability over `http://` and outside the service URL, which
  SpaceTAP reads with `https://`.

### ESO

`https://archive.eso.org/tap_obs`

### VizieR and SIMBAD (CDS)

- VizieR: `https://tapvizier.cds.unistra.fr/TAPVizieR/tap`
- SIMBAD: `https://simbad.cds.unistra.fr/simbad/sim-tap`

Both were last checked on 27 October 2026, with sync queries in CSV only. They
didn't answer on the later dates.

### CADC

`https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus`

- Redirects each query to its result with a 303 (TAP 1.1 §2.1), which SpaceTAP
  follows.
- Sends query errors as plain text with HTTP 400, which SpaceTAP returns as a
  `:service_error`.

### NASA Exoplanet Archive

`https://exoplanetarchive.ipac.caltech.edu/TAP`

- Labels CSV `text/plain`.
- Applies `TOP` before `ORDER BY`, so use `:maxrec` to get the first rows of a
  sorted result.
- Answers that an async job is deleted, and keeps it for 4 days.

### IRSA (IPAC)

`https://irsa.ipac.caltech.edu/TAP`

- Sends the CSV result of an async job labelled as VOTable, so pass
  `format: :votable`.
- Answers that an async job is deleted, and keeps it.
- Writes a column's `arraysize` as a number, `"1"` for a single value.

### NED (IPAC)

`https://ned.ipac.caltech.edu/tap`

- Its `TAP_SCHEMA` follows TAP 1.0: columns have no `arraysize` or `xtype`, and
  an ADQL type such as `BIGINT` as `datatype`.

### KOA (Keck)

`https://koa.ipac.caltech.edu/TAP`

- Labels CSV `text/plain`.
- Sends query errors as plain text with HTTP 400, which SpaceTAP returns as a
  `:service_error`.
- Applies `TOP` before `ORDER BY`, so use `:maxrec` to get the first rows of a
  sorted result.
- Answers that an async job is deleted, and keeps it for 4 days.
- Sends its capabilities and availability with no `Content-Type`, which
  SpaceTAP reads as XML.

### MAST

`https://mast.stsci.edu/vo-tap/api/v0.1/caom`

- Sends VOTable even when CSV is requested of a sync query, so pass
  `format: :votable`.
- Sends CSV as the result of an async job.
- Marks every VOTable result as overflow, even one with no rows, so `overflow`
  is always `true`, and `tables/2` and `columns/3` log a warning.

## Development

Run the unit tests, which don't need network access:

```sh
mix test
```

Integration tests run queries against GAVO, on its copy of Gaia DR3, and are
excluded by default:

```sh
mix test --include integration
```

Parity tests run the same queries through SpaceTAP and through
[PyVO][pyvo], an Astropy-affiliated Python client for IVOA services, and
compare the results: the columns, the overflow and the value of every cell.
They need [`uv`][uv]. Those for GAVO run with:

```sh
mix test --only pyvo
```

Parity tests on the fixtures have SpaceTAP and PyVO read each VOTable fixture,
with no network, and CI runs them on every pull request:

```sh
mix test --only pyvo_fixtures
```

`mix test.release` runs the unit, integration and parity tests above. Run it
before a release.

Services tests send the queries of the fixtures to every service in
[Compatibility](#compatibility), check that they still answer the same way, and
run their parity tests. They are slow, and a failure is a
reason to look into that service, not to hold a release, so `mix test.release`
leaves them out:

```sh
mix test.services
```

The [`livebooks`](https://github.com/jaimeiniesta/space_tap/tree/main/livebooks) folder has [Livebook](https://livebook.dev)
notebooks that run SpaceTAP against Gaia DR3 at GAVO, the NASA Exoplanet
Archive and other services, with tables and charts, and one that runs the parity tests'
queries through SpaceTAP and PyVO side by side. They install SpaceTAP from Hex,
and each one has a "Run in Livebook" button on HexDocs.

## About

SpaceTAP started as an exploration of the astronomy software ecosystem from
Elixir: how libraries such as Python's [PyVO][pyvo] and [Astroquery][astroquery]
work, and what Elixir can bring to it. It is written with AI coding tools; I
review, test and answer for every change.

## Contributing

Contributions made with AI tools are welcome, but a person must open, supervise
and answer for every issue and pull request. See [AGENTS.md](https://github.com/jaimeiniesta/space_tap/blob/main/AGENTS.md).

## License

MIT. See [LICENSE](https://github.com/jaimeiniesta/space_tap/blob/main/LICENSE).

[adql]: https://www.ivoa.net/documents/ADQL/
[astroquery]: https://astroquery.readthedocs.io/
[explorer]: https://hexdocs.pm/explorer/
[gaia]: https://gea.esac.esa.int/archive/
[kino_explorer]: https://hexdocs.pm/kino_explorer/
[pyvo]: https://pyvo.readthedocs.io/
[req]: https://hexdocs.pm/req/
[tap]: https://www.ivoa.net/documents/TAP/
[uv]: https://docs.astral.sh/uv/
