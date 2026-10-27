<p align="center">
  <img src="assets/space_tap_logo.png" alt="SpaceTAP: an Elixir client for the IVOA Table Access Protocol" width="400">
</p>

# SpaceTAP

SpaceTAP is an Elixir client for the IVOA [Table Access Protocol][tap] (TAP),
the HTTP protocol astronomical archives use to expose their tables. You send a
query written in [ADQL][adql], a dialect of SQL with functions for positions on
the sky, and get the table back as Elixir data.

It is not related to the Test Anything Protocol, which shares the acronym.

## Installation

Add `space_tap` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:space_tap, "~> 0.1.0"}
  ]
end
```

In Livebook or a script:

```elixir
Mix.install([{:space_tap, "~> 0.1.0"}])
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

The result is a `SpaceTAP.Result`: `columns` holds the column names in order,
and each row is a list with one value per column, in the same order. To work
with maps instead:

```elixir
Enum.map(result.rows, fn row -> Map.new(Enum.zip(result.columns, row)) end)
```

### Options

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

`:status` holds the HTTP status, and `Exception.message/1` starts with it:

```elixir
{:error, error} =
  SpaceTAP.query(service_url, "SELECT TOP 3 source_id FROM gaiadr3.no_such_table")

error.type
#=> :service_error

Exception.message(error)
#=> "(HTTP 400) Cannot parse query 'SELECT TOP 3 source_id FROM gaiadr3.no_such_table' ..."
```

## Results come as CSV

SpaceTAP 0.1 asks the service for CSV. That keeps it small, but CSV carries
less than VOTable, the IVOA format for tables:

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

Typed results read from VOTable are planned for a later version, along with
async queries for long-running and large results.

## Compatibility

SpaceTAP follows [TAP 1.1][tap] and works with TAP 1.0 services. It is tested
against the Gaia archive.

## Development

Run the unit tests, which don't need network access:

```sh
mix test
```

Integration tests run queries against the Gaia archive and are excluded by
default:

```sh
mix test --include integration
```

Parity tests run the same queries through SpaceTAP and through
[pyvo][pyvo], the IVOA client for Python, and compare the results. They need
[`uv`][uv]:

```sh
mix test --only pyvo
```

`mix test.all` runs all three suites. Run it before a release.

## About

SpaceTAP started as an exploration of the astronomy software ecosystem from
Elixir: how libraries such as Python's [pyvo][pyvo] and [Astroquery][astroquery]
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
