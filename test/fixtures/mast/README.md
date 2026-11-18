# MAST fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of the CAOM TAP service of MAST, the archive at
STScI, captured on 2026-10-27 (`syntax_error.xml` on 2026-10-28) with:

```bash
curl -sS -L -o <file> https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tables.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables` | 200 | `text/xml; charset=utf-8` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `text/xml; charset=utf-8` |

MAST sends a VOTable (TABLEDATA) although CSV was requested, with `FORMAT=csv`
and with `RESPONSEFORMAT=csv`. TAP 1.1 §2.7.3 requires VOTable and only
recommends CSV, so SpaceTAP returns a `:decode_error` until it reads VOTable.
Its error document is a VOTable too, which SpaceTAP reads as a `:service_error`.

Asked again on 2026-11-10 with `FORMAT=votable`, MAST sent `tables.xml` byte for byte.

## Job documents

The files in `jobs/` are job documents: what MAST returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://mast.stsci.edu/vo-tap/api/v0.1/caom/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name` | COMPLETED | `text/xml; charset=utf-8` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml; charset=utf-8` |

The job ran inside the request that created it, so it had ended by the
first GET. The documents have no XML declaration, and the job in ERROR lists a
result too.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what MAST answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://mast.stsci.edu/vo-tap/api/v0.1/caom/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'ivoa'` | 200 | `text/xml; charset=utf-8` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'ivoa.obscore'` | 200 | `text/xml; charset=utf-8` |

Both end with a second `QUERY_STATUS`, `OVERFLOW`, after the table, although the first holds one row and the second 31. MAST marked every result as overflow that day, with `MAXREC=100000` and with no rows.
