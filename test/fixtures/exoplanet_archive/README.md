# NASA Exoplanet Archive fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of the NASA Exoplanet Archive, run by IPAC,
captured on 2026-10-27 with:

```bash
curl -sS -o <file> https://exoplanetarchive.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `planets.csv` | `SELECT TOP 3 pl_name, disc_year FROM ps` | 200 | `text/plain` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `application/xml` |

The CSV comes as `text/plain` instead of `text/csv`, which SpaceTAP reads as CSV
(`docs/adr/0003-csv-sent-as-plain-text-is-read-as-csv.md`). It has LF line
endings and quotes every string value.

On 2026-11-10 the archive answered `FORMAT=votable` with HTTP 503 and a
maintenance page. The VOTable result was captured on 2026-11-13 with the same
request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `planets.xml` | `SELECT TOP 3 pl_name, disc_year FROM ps` | 200 | `application/xml` |

It is VOTable 1.3 with TABLEDATA rows, and writes each string cell and the
description in CDATA. With no `ORDER BY`, `TOP 3` gave other planets than in
`planets.csv`.

## Job documents

The files in `jobs/` are job documents: what the NASA Exoplanet Archive returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://exoplanetarchive.ipac.caltech.edu/TAP/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name` | COMPLETED | `application/xml` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `application/xml` |

The job ran inside the request that created it, so it had ended by the
first GET. The `Location` is `http://exoplanetarchive.ipac.caltech.edu//TAP/async/<id>`,
with `http` and a double slash, and `http` answers 301 to `https`. The
documents have no `version`, bind `xsi` to `http://www.w3.org/2001/XMLSchema`
instead of `…/XMLSchema-instance`, and give local times without a zone. The
href of the result is under `/workspace/`, with `http`. `DELETE` on the job
answered 502, and `ACTION=DELETE` answered 200 but left the job in place.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what the NASA Exoplanet Archive answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://exoplanetarchive.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'exo_tap'` | 200 | `application/xml` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'ps'` | 200 | `application/xml` |

The schema has 41 rows, `stellarhosts` twice, and the table `ps` 355 columns, which add `format`.

## VOSI

`capabilities.xml` and `availability.xml` are the documents the NASA Exoplanet Archive served on 2026-11-18 for `SpaceTAP.availability/2`, captured with:

```bash
curl -sS -o capabilities.xml https://exoplanetarchive.ipac.caltech.edu/TAP/capabilities
curl -sS -L -o availability.xml http://exoplanetarchive.ipac.caltech.edu/TAP/availability
```

| File | URL | HTTP | Content-Type |
|---|---|---|---|
| `capabilities.xml` | `https://exoplanetarchive.ipac.caltech.edu/TAP/capabilities` | 200 | `application/xml` |
| `availability.xml` | `http://exoplanetarchive.ipac.caltech.edu/TAP/availability`, the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability | 200 | `application/xml` |

The archive lists its availability over `http://` and redirects it to `https://` with a 301, which `-L` follows.
