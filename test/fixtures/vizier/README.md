# VizieR fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of VizieR, the catalogue service of the CDS,
captured on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://tapvizier.cds.unistra.fr/TAPVizieR/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `hip_main.csv` | `SELECT TOP 5 HIP, RAICRS, DEICRS, Vmag, Plx, "B-V", SpType FROM "I/239/hip_main" WHERE HIP <= 5` | 200 | `text/csv;charset=UTF-8` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `application/xml;charset=UTF-8` |

The table name and `B-V` need double quotes in ADQL: they aren't regular
identifiers (ADQL 2.1 §2.1.6). Some numbers come in E notation (`9.1185E-4`).
