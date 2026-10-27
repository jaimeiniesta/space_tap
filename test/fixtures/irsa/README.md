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
