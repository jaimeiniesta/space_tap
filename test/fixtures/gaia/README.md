# Gaia fixtures

Keep these files byte for byte as Gaia sent them: don't reformat or edit them.
A pretty-printer would, for example, add the XML declaration that Gaia's error
documents lack. To read one indented, run `xmllint --format <file>`; to change
one, capture it again.

Responses from the Gaia archive sync endpoint, captured on 2026-10-22 with:

```bash
curl -sS -o <file> https://gea.esac.esa.int/tap-server/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Extra parameters | Query |
|---|---|---|
| `pleiades.csv` | | `SELECT TOP 5 source_id, designation, ra, dec, parallax, phot_g_mean_mag FROM gaiadr3.gaia_source WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag` |
| `nulls.csv` | | `SELECT TOP 3 source_id, designation, ra, dec, parallax FROM gaiadr3.gaia_source WHERE parallax IS NULL` |
| `maxrec_0.csv` | `MAXREC=0` | `SELECT TOP 3 source_id, ra, dec FROM gaiadr3.gaia_source` |
| `nulls_single_column.csv` | | `SELECT TOP 3 parallax FROM gaiadr3.gaia_source WHERE parallax IS NULL` |

All came back with HTTP 200, `Content-Type: text/csv` and LF line endings.
`nulls_single_column.csv` was captured on 2026-10-27: each NULL row is an empty
line after the header.

The VOTable documents were captured on 2026-10-23 with the same request:

| File | Extra parameters | Query | HTTP | Content-Type |
|---|---|---|---|---|
| `ok.xml` | `FORMAT=votable` (instead of `csv`) | `SELECT TOP 3 source_id FROM gaiadr3.gaia_source` | 200 | `application/x-votable+xml` |
| `syntax_error.xml` | | `SELEC TOP 3 source_id FROM gaiadr3.gaia_source` | 400 | `application/xml;charset=UTF-8` |
| `unknown_table.xml` | | `SELECT TOP 3 source_id FROM gaiadr3.no_such_table` | 400 | `application/xml;charset=UTF-8` |
| `overflow.xml` | `FORMAT=votable` (instead of `csv`), `MAXREC=3` | `SELECT TOP 10 source_id FROM gaiadr3.gaia_source` | 200 | `application/x-votable+xml` |

The error documents are VOTable 1.2 with no XML declaration, and Gaia sends them
although CSV was requested. `ok.xml` has a single `QUERY_STATUS` of `OK` before
the table; `overflow.xml` is the same document with a second one, `OVERFLOW`,
after it. Both carry their table data as BINARY2.
