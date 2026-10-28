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
