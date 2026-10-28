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
