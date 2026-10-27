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
