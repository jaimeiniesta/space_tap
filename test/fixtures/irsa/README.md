# IRSA fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of IRSA, the infrared archive at IPAC, captured
on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://irsa.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `columns.csv` | `SELECT TOP 5 table_name, column_name, datatype, unit, description FROM TAP_SCHEMA.columns WHERE table_name = 'fp_psc'` | 200 | `text/csv` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 200 | `text/xml` |

The query reads `TAP_SCHEMA` because queries on the 2MASS catalogue (`fp_psc`)
take from 45 seconds to over a minute. The error document comes with HTTP 200,
which TAP 1.1 §3.3 allows.

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `columns.xml` | `SELECT TOP 5 table_name, column_name, datatype, unit, description FROM TAP_SCHEMA.columns WHERE table_name = 'fp_psc'` | 200 | `application/x-votable+xml` |

Its rows are TABLEDATA.

## Job documents

The files in `jobs/` are job documents: what IRSA returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://irsa.ipac.caltech.edu/TAP/async \
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
| `jobs/queued.xml` | the same as `completed.xml`, at the first GET | QUEUED | `text/xml` |

`queued.xml` is the job of `completed.xml` before it ran, and already lists
the URL of its result. The documents have no `version`. Deleting the job
answered 200 but left it in place.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what IRSA answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://irsa.ipac.caltech.edu/TAP/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = '2mass'` | 200 | `application/x-votable+xml` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'fp_psc'` | 200 | `application/x-votable+xml` |

IRSA puts `table_index` and `column_index` first, adds columns of its own named `irsa_*`, and declares `arraysize` as an `int`, 1 for a single value.

## VOSI

`capabilities.xml` and `availability.xml` are the documents IRSA served on 2026-11-18 for `SpaceTAP.availability/2`, captured with:

```bash
curl -sS -o capabilities.xml https://irsa.ipac.caltech.edu/TAP/capabilities
curl -sS -o availability.xml https://irsa.ipac.caltech.edu/TAP/availability
```

| File | URL | HTTP | Content-Type |
|---|---|---|---|
| `capabilities.xml` | `https://irsa.ipac.caltech.edu/TAP/capabilities` | 200 | `text/xml` |
| `availability.xml` | `https://irsa.ipac.caltech.edu/TAP/availability`, the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability | 200 | `text/xml` |
