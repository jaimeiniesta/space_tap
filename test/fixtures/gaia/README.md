# Gaia fixtures

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

All came back with HTTP 200, `Content-Type: text/csv` and LF line endings.
