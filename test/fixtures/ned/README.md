# NED fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of NED, the NASA/IPAC Extragalactic Database,
captured on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://ned.ipac.caltech.edu/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `objdir.csv` | `SELECT TOP 5 prefname, prefphytype, ra, dec, z, zflag FROM NEDTAP.objdir WHERE CONTAINS(POINT('J2000', ra, dec), CIRCLE('J2000', 56.75, 24.12, 0.2)) = 1` | 200 | `text/csv;charset=UTF-8` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `application/xml;charset=UTF-8` |

`NEDTAP.objdir` is the only table besides `TAP_SCHEMA`. Strings are quoted, and
the empty cells are NULLs.

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `objdir.xml` | `SELECT TOP 5 prefname, prefphytype, ra, dec, z, zflag FROM NEDTAP.objdir WHERE CONTAINS(POINT('J2000', ra, dec), CIRCLE('J2000', 56.75, 24.12, 0.2)) = 1` | 200 | `application/x-votable+xml;charset=UTF-8` |

Its rows are BINARY. The NULLs of the CSV are NaN in `z` and empty strings in `prefphytype` and `zflag`, since BINARY has no null flags, and SpaceTAP reads both as `nil` (`docs/adr/0007-how-votable-values-map-to-elixir.md`).

## Job documents

The files in `jobs/` are job documents: what NED returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://ned.ipac.caltech.edu/tap/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name` | COMPLETED | `text/xml;charset=UTF-8` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml;charset=UTF-8` |

The job ran inside the request that created it, so it had ended by the
first GET. The documents use a default namespace instead of the `uws` prefix
and give times with a UTC offset, such as `2026-11-16T11:01:17-08:00`, which
PyVO 1.9.1 can't read. The `Location` and the href of the result have the port,
`https://ned.ipac.caltech.edu:443/tap/async/<id>`. `DELETE` on the job answered
403, and `ACTION=DELETE` deleted it.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what NED answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://ned.ipac.caltech.edu/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'NEDTAP'` | 200 | `application/x-votable+xml;charset=UTF-8` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'NEDTAP.objdir'` | 200 | `application/x-votable+xml;charset=UTF-8` |

NED's `TAP_SCHEMA.columns` follows TAP 1.0: it has no `arraysize` or `xtype`, `datatype` holds ADQL types such as `BIGINT`, and `std` is empty. It adds `coosys_id`.
