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
