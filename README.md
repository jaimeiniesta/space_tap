<p align="center">
  <img src="assets/space_tap_logo.png" alt="SpaceTAP: an Elixir client for the IVOA Table Access Protocol" width="400">
</p>

# SpaceTAP

SpaceTAP is an Elixir client for the IVOA [Table Access Protocol][tap] (TAP),
the HTTP protocol astronomical archives use to expose their tables. You send a
query written in [ADQL][adql], a dialect of SQL with functions for positions on
the sky, and get the table back as Elixir data.

It is not related to the Test Anything Protocol, which shares the acronym.

Coming from Python? The
[parity livebook](https://github.com/jaimeiniesta/space_tap/blob/main/livebooks/pyvo_parity.livemd)
runs the same queries through [PyVO][pyvo] and SpaceTAP side by side.

## Installation

Add `space_tap` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:space_tap, "~> 0.2.0"}
  ]
end
```

In Livebook or a script:

```elixir
Mix.install([{:space_tap, "~> 0.2.0"}])
```

## Usage

`SpaceTAP.query/3` takes the service URL of a TAP service and an ADQL query.
This one asks the [Gaia archive][gaia] for the five brightest stars within one
degree of the centre of the Pleiades:

```elixir
adql = """
SELECT TOP 5 source_id, ra, dec, parallax, phot_g_mean_mag
FROM gaiadr3.gaia_source
WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1
  AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL
ORDER BY phot_g_mean_mag
"""

{:ok, result} = SpaceTAP.query("https://gea.esac.esa.int/tap-server/tap", adql)

result.columns
#=> ["source_id", "ra", "dec", "parallax", "phot_g_mean_mag"]

hd(result.rows)
#=> ["66526127137440128", "57.29068893293528", "24.053211829998986",
#=>  "8.118448445799721", "3.6157947"]
```

The service URL is the base URL of the service, what TAP calls its access URL.
SpaceTAP sends the query to its `/sync` endpoint, so pass the base URL even if
you know the endpoint.

Use the `https://` URL when the service has one. Gaia, for example, redirects
`http://` to `https://` with a 302. Req, like curl and PyVO, follows a 301 or
302 with a GET, as RFC 9110 allows (§15.4.2, §15.4.3), and the GET carries no
query. The request then fails, with an error that depends on the service: Gaia
answers with its list of async jobs, which SpaceTAP returns as a
`:decode_error`.

The result is a `SpaceTAP.Result`: `columns` holds the column names in order,
and each row is a list with one value per column, in the same order. To work
with maps instead:

```elixir
Enum.map(result.rows, fn row -> Map.new(Enum.zip(result.columns, row)) end)
```

### Options

- `:format` is the format to ask the service for: `:csv`, the default, or
  `:votable`. See [CSV or VOTable](#csv-or-votable).
- `:maxrec` asks the service to return at most that many rows. The service may
  apply a lower limit of its own. `maxrec: 0` returns the columns with no rows.
- `:req_options` are passed to [Req][req], the HTTP client. Req waits 15 seconds
  for a response by default; for slower queries, raise it:

  ```elixir
  SpaceTAP.query(service_url, adql, req_options: [receive_timeout: 60_000])
  ```

  SpaceTAP sets the TAP request itself, but some Req options, such as
  `:headers`, can still change it. See `SpaceTAP.query/3`.

### Errors

A failed query returns `{:error, %SpaceTAP.Error{}}`, whose `:type` says what
went wrong:

| Type | When |
|---|---|
| `:service_error` | The service rejected the query, for example because of invalid ADQL or an unknown table. `:message` is the service's own message. |
| `:http_error` | An HTTP error status without an error document from the service, such as a proxy's 502 page. |
| `:transport_error` | No response arrived: the connection failed or timed out. |
| `:decode_error` | A successful response that can't be read as a result, such as malformed CSV. |

Later versions may add types, so when you match on `:type`, keep a clause for
the rest.

`:status` holds the HTTP status, and `Exception.message/1` starts with it:

```elixir
{:error, error} =
  SpaceTAP.query(service_url, "SELECT TOP 3 source_id FROM gaiadr3.no_such_table")

error.type
#=> :service_error

Exception.message(error)
#=> "(HTTP 400) Cannot parse query 'SELECT TOP 3 source_id FROM gaiadr3.no_such_table' ..."
```

## CSV or VOTable

SpaceTAP asks the service for CSV by default, as it did in 0.1. CSV is simple,
but it carries less than VOTable, the IVOA format for tables:

- **Every value is a string.** CSV has no types, so `"8.118448445799721"`
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
{:ok, result} =
  SpaceTAP.query("https://gea.esac.esa.int/tap-server/tap", adql, format: :votable)

hd(result.rows)
#=> [66526127137440128, 57.29068893293528, 24.053211829998986,
#=>  8.118448445799721, 3.6157946586608887]

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
  or at a limit of its own (DALI 1.1 §4.4.1).

`phot_g_mean_mag` is a `float`, a 32-bit number, and SpaceTAP gives the exact
value of its 32 bits as an Elixir float: `3.6157946586608887`, where the CSV
says `3.6157947`. Both are the same number, and PyVO reads the same value.

The service picks how the rows travel inside the VOTable, and SpaceTAP reads
the three serializations TAP services send: TABLEDATA, BINARY and BINARY2. A
VOTable that comes when CSV was asked for, as MAST sends, is a `:decode_error`
that says to pass `format: :votable`, so the value types don't depend on the
service.

Async queries, for long-running and large results, are planned for a later
version.

## Compatibility

SpaceTAP follows [TAP 1.1][tap] and works with TAP 1.0 services. It has been
checked against these services, last on 15 November 2026, except four that
didn't answer that day: Gaia was last checked on 13 November, IRSA on 10
November, and VizieR and SIMBAD, both run by CDS, on 27 October, with CSV only.

| Service | Service URL | Formats | Checked by | Notes |
|---|---|---|---|---|
| [Gaia archive][gaia] (ESA) | `https://gea.esac.esa.int/tap-server/tap` | CSV, VOTable | Integration and parity tests, fixtures, livebooks | Redirects `http://` to `https://`, which loses the query: use `https://`. |
| GAVO Data Center | `https://dc.g-vo.org/tap` | CSV, VOTable | Services and parity tests, fixtures, livebooks | Runs DaCHS. Sends error documents with HTTP 500. |
| NASA Exoplanet Archive | `https://exoplanetarchive.ipac.caltech.edu/TAP` | CSV, VOTable | Integration and parity tests, fixtures, livebooks | Labels CSV `text/plain`. Applies `TOP` before `ORDER BY`, so use `:maxrec` to get the first rows of a sorted result. |
| IRSA (IPAC) | `https://irsa.ipac.caltech.edu/TAP` | CSV, VOTable | Services and parity tests, fixtures, livebook | |
| NED (IPAC) | `https://ned.ipac.caltech.edu/tap` | CSV, VOTable | Services and parity tests, fixtures, livebook | |
| KOA (Keck) | `https://koa.ipac.caltech.edu/TAP` | CSV, VOTable | Services and parity tests, fixtures, livebook | Labels CSV `text/plain`. Sends query errors as plain text with HTTP 400, which SpaceTAP returns as a `:service_error`. |
| VizieR (CDS) | `https://tapvizier.cds.unistra.fr/TAPVizieR/tap` | CSV; VOTable not checked yet | Services and parity tests, fixtures, livebook | |
| SIMBAD (CDS) | `https://simbad.cds.unistra.fr/simbad/sim-tap` | CSV; VOTable not checked yet | Services and parity tests, fixtures, livebook | |
| ESO | `https://archive.eso.org/tap_obs` | CSV, VOTable | Services and parity tests, fixtures, livebook | |
| CADC | `https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus` | CSV, VOTable | Services and parity tests, fixtures, livebook | Redirects each query to its result with a 303 (TAP 1.1 §2.1), which SpaceTAP follows. Sends query errors as plain text with HTTP 400, which SpaceTAP returns as a `:service_error`. |
| MAST | `https://mast.stsci.edu/vo-tap/api/v0.1/caom` | VOTable only | Services and parity tests, fixtures, livebook | Sends VOTable even when CSV is requested, so pass `format: :votable`. |

Integration, services and parity tests query the live service (see
[Development](#development)), and fixtures are its responses, captured for the
unit tests. The
[tour of TAP services](https://github.com/jaimeiniesta/space_tap/blob/main/livebooks/tap_services_tour.livemd)
livebook queries all of them. Services change, so one that worked here may
behave differently today.

## Development

Run the unit tests, which don't need network access:

```sh
mix test
```

Integration tests run queries against the Gaia archive and the NASA Exoplanet
Archive, and are excluded by default:

```sh
mix test --include integration
```

Parity tests run the same queries through SpaceTAP and through
[PyVO][pyvo], an Astropy-affiliated Python client for IVOA services, and
compare the results: the columns, the overflow and the value of every cell.
They need [`uv`][uv]. Those for Gaia and the NASA Exoplanet Archive run with:

```sh
mix test --only pyvo
```

`mix test.release` runs the unit, integration and parity tests above. Run it
before a release.

Services tests send the queries of the fixtures to the other services in
[Compatibility](#compatibility), check that they still answer the same way, and
run their parity tests. They are slow, and a failure is a
reason to look into that service, not to hold a release, so `mix test.release`
leaves them out:

```sh
mix test.services
```

The [`livebooks`](https://github.com/jaimeiniesta/space_tap/tree/main/livebooks) folder has [Livebook](https://livebook.dev)
notebooks that run SpaceTAP against Gaia, GAVO, the NASA Exoplanet Archive and
other services, with tables and charts, and one that runs the parity tests'
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
[gaia]: https://gea.esac.esa.int/archive/
[pyvo]: https://pyvo.readthedocs.io/
[req]: https://hexdocs.pm/req/
[tap]: https://www.ivoa.net/documents/TAP/
[uv]: https://docs.astral.sh/uv/
