# Gaia fixtures

Keep these files byte for byte as Gaia sent them: don't reformat or edit them.
A pretty-printer would, for example, add the XML declaration that Gaia's error
documents lack. To read one indented, run `xmllint --format <file>`; to change
one, capture it again.

Responses from the Gaia archive sync endpoint, captured on 2026-10-22 with:

```bash
curl -sS -o <file> https://gea.esac.esa.int/tap-server/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Extra parameters | Query |
|---|---|---|
| `pleiades.csv` | | `SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag` |
| `nulls.csv` | | `SELECT TOP 3 source_id, designation, ra, dec, parallax FROM gaiadr3.gaia_source WHERE parallax IS NULL` |
| `maxrec_0.csv` | `MAXREC=0` | `SELECT TOP 3 source_id, ra, dec FROM gaiadr3.gaia_source` |
| `nulls_single_column.csv` | | `SELECT TOP 3 parallax FROM gaiadr3.gaia_source WHERE parallax IS NULL` |

All came back with HTTP 200, `Content-Type: text/csv` and LF line endings.
`nulls_single_column.csv` was captured on 2026-10-27: each NULL row is an empty
line after the header.

The VOTable documents were captured on 2026-10-23 with the same request:

| File | Extra parameters | Query | HTTP | Content-Type |
|---|---|---|---|---|
| `ok.xml` | `FORMAT=votable` (instead of `csv`) | `SELECT TOP 3 source_id FROM gaiadr3.gaia_source` | 200 | `application/x-votable+xml` |
| `syntax_error.xml` | | `SELEC TOP 3 source_id FROM gaiadr3.gaia_source` | 400 | `application/xml;charset=UTF-8` |
| `unknown_table.xml` | | `SELECT TOP 3 source_id FROM gaiadr3.no_such_table` | 400 | `application/xml;charset=UTF-8` |
| `overflow.xml` | `FORMAT=votable` (instead of `csv`), `MAXREC=3` | `SELECT TOP 10 source_id FROM gaiadr3.gaia_source` | 200 | `application/x-votable+xml` |

The error documents are VOTable 1.2 with no XML declaration, and Gaia sends them
although CSV was requested. `ok.xml` has a single `QUERY_STATUS` of `OK` before
the table; `overflow.xml` is the same document with a second one, `OVERFLOW`,
after it. Both carry their table data as BINARY2.

`sync_get.xml` is Gaia's answer to a `GET /sync` with no parameters, which is
what a client sends after Gaia redirects `http://` to `https://` with a 302 and
the POST becomes a GET. It came back with HTTP 200 and
`Content-Type: text/xml;charset=UTF-8`: an empty list of async jobs, which isn't
a result. Captured on 2026-10-27 with:

```bash
curl -sS -o sync_get.xml https://gea.esac.esa.int/tap-server/tap/sync
```

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `pleiades.xml` | `SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag` | 200 | `application/x-votable+xml` |

Its rows are BINARY2. Besides the table, its results `RESOURCE` holds `PARAM`s, each with a `DESCRIPTION`, and a nested `RESOURCE`, and a `RESOURCE` of type `meta` with DataLink service descriptors follows it.

A result with two columns of the same name was captured on 2026-11-18 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `repeated_names.xml` | `SELECT TOP 1 table_name, table_name FROM TAP_SCHEMA.tables` | 200 | `application/x-votable+xml` |

Gaia names both `FIELD`s `table_name`, with no `ID`. Its rows are BINARY2.

## Job documents

The files in `jobs/` are job documents: what the Gaia archive returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://gea.esac.esa.int/tap-server/tap/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag` | COMPLETED | `text/xml;charset=UTF-8` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml;charset=UTF-8` |
| `jobs/executing.xml` | the same as `completed.xml`, at the first GET | EXECUTING | `text/xml;charset=UTF-8` |

`executing.xml` is the job of `completed.xml` while it ran. The documents
say `version="1.0"` and write values in CDATA sections. They also repeat the IP
address and the User-Agent of the client that created the job. The IP address
is the one change made to a captured file: it was replaced with `192.0.2.1`, an
address reserved for documentation (RFC 5737).

## VOSI

`capabilities.xml` and `availability.xml` are the documents the Gaia archive served on 2026-11-18 for `SpaceTAP.availability/2`, captured with:

```bash
curl -sS -o capabilities.xml https://gea.esac.esa.int/tap-server/tap/capabilities
curl -sS -o availability.xml https://gea.esac.esa.int/tap-server/tap/availability
```

| File | URL | HTTP | Content-Type |
|---|---|---|---|
| `capabilities.xml` | `https://gea.esac.esa.int/tap-server/tap/capabilities` | 200 | `text/xml;charset=UTF-8` |
| `availability.xml` | `https://gea.esac.esa.int/tap-server/tap/availability`, the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability | 200 | `text/xml;charset=UTF-8` |

The access URL has white space around it.
