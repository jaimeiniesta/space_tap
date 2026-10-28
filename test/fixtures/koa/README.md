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
