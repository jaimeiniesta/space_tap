# SIMBAD fixtures

Keep these files byte for byte as the service sent them: don't reformat or edit
them. To change one, capture it again.

Responses from the sync endpoint of SIMBAD, the astronomical object database of
the CDS, captured on 2026-10-27 with:

```bash
curl -sS -L -o <file> https://simbad.cds.unistra.fr/simbad/sim-tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `basic.csv` | `SELECT TOP 5 main_id, ra, dec, otype, sp_type, plx_value FROM basic WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 0.1)) = 1` | 200 | `text/csv;charset=UTF-8` |
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM TAP_SCHEMA.tables` | 400 | `application/xml;charset=UTF-8` |

Object names keep their runs of spaces (`Cl* Melotte   22     VM      13`), and
the empty cells are NULLs.
