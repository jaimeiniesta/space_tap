# CADC fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of CADC, the Canadian Astronomy Data Centre,
captured on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `obscore.csv` | `SELECT TOP 5 obs_id, obs_collection, target_name, s_ra, s_dec, instrument_name, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1` | 303, then 200 | `text/csv; header=present` |
| `syntax_error.txt` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 303, then 400 | `text/plain` |

CADC answers the POST with HTTP 303 and the URL of the job's result, which is
how TAP 1.1 §2.1 allows a sync query to answer. `-L` follows it, and the files
are the responses to the GET. The error is plain text with HTTP 400, which
SpaceTAP returns as a `:service_error`
(`docs/adr/0004-plain-text-with-400-is-a-service-error.md`). The message is
written as a single CSV field (in quotes, with doubled `"`), and SpaceTAP keeps
it that way.

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `obscore.xml` | `SELECT TOP 5 obs_id, obs_collection, target_name, s_ra, s_dec, instrument_name, em_min FROM ivoa.ObsCore WHERE CONTAINS(POINT('ICRS', s_ra, s_dec), CIRCLE('ICRS', 56.75, 24.12, 0.5)) = 1` | 303, then 200 | `application/x-votable+xml; serialization=tabledata` |

Its rows are TABLEDATA, and its strings have an `arraysize` with a maximum, such as `128*`.

## Job documents

The files in `jobs/` are job documents: what CADC returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://ws.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/argus/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

CADC ignores the `PHASE=RUN` of the first request and leaves the job PENDING,
so a third request started it, between the two:

```bash
curl -sS -X POST <job URL>/phase --data-urlencode "PHASE=RUN"
```

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 3 table_name FROM TAP_SCHEMA.tables ORDER BY table_name` | COMPLETED | `text/xml` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml` |

Besides the result, the job lists results named `diag` and `rowcount`, whose
hrefs aren't URLs, such as `uws:executing:1`. The result is on another host,
`ws-cadc.canfar.net`.
