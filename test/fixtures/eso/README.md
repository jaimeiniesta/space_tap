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
