# KOA fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of KOA, the Keck Observatory Archive at IPAC,
captured on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://koa.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `hires.csv` | `SELECT TOP 5 koaid, instrume, targname, ra, dec, date_obs, progtitl FROM koa_hires` | 200 | `text/plain; charset=UTF-8` |
| `syntax_error.txt` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `text/plain; charset=UTF-8` |

The CSV comes as `text/plain`, which SpaceTAP reads as CSV
(`docs/adr/0003-csv-sent-as-plain-text-is-read-as-csv.md`). The error is plain
text with HTTP 400, which SpaceTAP returns as a `:service_error`
(`docs/adr/0004-plain-text-with-400-is-a-service-error.md`).

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `hires.xml` | `SELECT TOP 5 koaid, instrume, targname, ra, dec, date_obs, progtitl FROM koa_hires` | 200 | `text/xml` |

Its rows are TABLEDATA. KOA writes each string cell and each `DESCRIPTION` in a CDATA section, the descriptions with a space at each end.

## Job documents

The files in `jobs/` are job documents: what KOA returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://koa.ipac.caltech.edu/TAP/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name` | COMPLETED | `text/xml` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml` |

The job ran inside the request that created it, so it had ended by the
first GET. The documents have no `version`, bind `xsi` to
`http://www.w3.org/2001/XMLSchema`, spell `executionduration` in lower case,
and give local times without a zone, but with a `Z` in `destruction`. The href
of the result is under `/workspace/` and comes as `text/xml`, where
`<job>/results/result` comes as `text/plain`. The error message writes its
quotes as character references. `DELETE` on the job answered 500, and
`ACTION=DELETE` answered 200 but left the job in place.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what KOA answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://koa.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'koa_tap'` | 200 | `text/xml` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'koa_hires'` | 200 | `text/xml` |

The table `koa_hires` has 381 columns, which add `format`.

## VOSI

`capabilities.xml` and `availability.xml` are the documents KOA served on 2026-11-18 for `SpaceTAP.availability/2`, captured with:

```bash
curl -sS -o capabilities.xml https://koa.ipac.caltech.edu/TAP/capabilities
curl -sS -o availability.xml https://koa.ipac.caltech.edu/TAP/availability
```

| File | URL | HTTP | Content-Type |
|---|---|---|---|
| `capabilities.xml` | `https://koa.ipac.caltech.edu/TAP/capabilities` | 200 | none |
| `availability.xml` | `https://koa.ipac.caltech.edu/TAP/availability`, the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability | 200 | none |

Both came with no `Content-Type` header.
