# ESO fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of the ESO archive, captured on 2026-10-27
with:

```bash
curl -sS -L -o <file> https://archive.eso.org/tap_obs/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `obscore.csv` | `SELECT TOP 5 obs_id, target_name, s_ra, s_dec, instrument_name, dataproduct_type, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1` | 200 | `text/csv` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `application/xml` |

The error document has CRLF line endings.

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `obscore.xml` | `SELECT TOP 5 obs_id, target_name, s_ra, s_dec, instrument_name, dataproduct_type, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1` | 200 | `application/x-votable+xml` |

Its rows are TABLEDATA.

## Job documents

The files in `jobs/` are job documents: what ESO returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://archive.eso.org/tap_obs/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

ESO ignores the `PHASE=RUN` of the first request and leaves the job PENDING,
so a third request started it, between the two:

```bash
curl -sS -X POST <job URL>/phase --data-urlencode "PHASE=RUN"
```

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 5 obs_id, target_name, s_ra, s_dec, instrument_name, dataproduct_type, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1 ORDER BY obs_publisher_did` | COMPLETED | `text/xml;charset=UTF-8` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml;charset=UTF-8` |

The documents use a default namespace instead of the `uws` prefix, and list
the format asked for as `RESPONSEFORMAT`, with the value `VOTABLE`.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what ESO answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://archive.eso.org/tap_obs/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'ivoa'` | 200 | `application/x-votable+xml` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'ivoa.ObsCore'` | 200 | `application/x-votable+xml` |

`ivoa.ObsCore` has no `table_index`, and some of its columns no `column_index`.

## VOSI

`capabilities.xml` and `availability.xml` are the documents ESO served on 2026-11-18 for `SpaceTAP.availability/2`, captured with:

```bash
curl -sS -o capabilities.xml https://archive.eso.org/tap_obs/capabilities
curl -sS -o availability.xml https://archive.eso.org/tap_obs/availability
```

| File | URL | HTTP | Content-Type |
|---|---|---|---|
| `capabilities.xml` | `https://archive.eso.org/tap_obs/capabilities` | 200 | `application/xml` |
| `availability.xml` | `https://archive.eso.org/tap_obs/availability`, the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability | 200 | `application/xml;charset=UTF-8` |

ESO marks its VOSI access URLs `use="base"`, although VOSI 1.1 §4 requires `full`.
