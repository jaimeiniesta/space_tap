# GAVO fixtures

Keep these files byte for byte as GAVO sent them: don't reformat or edit them.
To read one indented, run `xmllint --format <file>`; to change one, capture it
again.

Responses from the sync endpoint of the GAVO data center, a DaCHS service,
captured on 2026-10-27 with:

```bash
curl -sS -o <file> https://dc.g-vo.org/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=csv" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `syntax_error.xml` | `SELEC TOP 3 table_name FROM tap_schema.tables` | 500 | `text/xml` |
| `hipparcos.csv` | `SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 5` | 200 | `text/csv;header=present` |

`hipparcos.csv` has CRLF line endings, as RFC 4180 uses, and spells the `sptype`
column `SpType`. Its `parallax` is in degrees.

The error document is VOTable 1.5 and starts with an `xml-stylesheet`
processing instruction and no XML declaration, which xmerl misread as a broken
declaration (issue #10). Saxy reads it.

The VOTable result was captured on 2026-11-10 with the same request and `FORMAT=votable` instead of `csv`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `hipparcos.xml` | `SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 5` | 200 | `application/x-votable+xml` |

Its rows are BINARY, and `hipno` has `VALUES null="-2147483648"`.

The Pleiades query of the README, on GAVO's copy of Gaia DR3, was captured on
2026-11-16 with the same request, `FORMAT=csv` and `FORMAT=votable`:

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `pleiades.csv` | `SELECT TOP 5 source_id, ra, dec, parallax, phot_g_mean_mag FROM gaia.dr3lite WHERE CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', 56.75, 24.12, 1.0)) = 1 AND parallax IS NOT NULL AND phot_g_mean_mag IS NOT NULL ORDER BY phot_g_mean_mag` | 200 | `text/csv;header=present` |
| `pleiades.xml` | the same | 200 | `application/x-votable+xml` |

They hold the same five stars as `gaia/pleiades.csv`, in the same order, but
`gaia.dr3lite` declares `parallax` a `float`, where Gaia's own archive has a
`double`, so the CSV writes `8.118448` where Gaia's writes `8.118448445799721`.
The VOTable rows are BINARY.

## Job documents

The files in `jobs/` are job documents: what GAVO returned for the URL
of an async job (TAP 1.1 §2.2, UWS 1.1 §2.2.1.1). They were captured on
2026-11-16 with:

```bash
curl -sS -D - -o /dev/null https://dc.g-vo.org/tap/async \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "PHASE=RUN" \
  --data-urlencode "QUERY=<query>"
curl -sS -o <file> <job URL>
```

The first request answers HTTP 303, with the URL of the job in `Location`, and
the second, repeated until the job ended, reads the job with HTTP 200.

GAVO ignores the `PHASE=RUN` of the first request and leaves the job PENDING,
so a third request started it, between the two:

```bash
curl -sS -X POST <job URL>/phase --data-urlencode "PHASE=RUN"
```

| File | Query | Phase | Content-Type |
|---|---|---|---|
| `jobs/completed.xml` | `SELECT TOP 5 hipno, ra, dec, vmag, parallax, sptype FROM hipparcos.main WHERE hipno <= 5` | COMPLETED | `text/xml` |
| `jobs/error.xml` | `SELECT TOP 1 nosuchcolumn FROM TAP_SCHEMA.tables` | ERROR | `text/xml` |
| `jobs/pending.xml` | the same as `completed.xml`, right after it was created | PENDING | `text/xml` |

`pending.xml` is the job of `completed.xml` before it ran. GAVO's
`Location` points to another path than the access URL,
`https://dc.g-vo.org/__system__/tap/run/async/<id>`, and the href of the result
starts with `http://`, which GAVO serves without redirecting to `https`. Like
its error documents, the job documents start with an `xml-stylesheet`
processing instruction and no XML declaration.

## TAP_SCHEMA

`tap_schema_tables.xml` and `tap_schema_columns.xml` are what GAVO answered on 2026-11-18 to the queries `SpaceTAP.tables/2` and `SpaceTAP.columns/3` send, captured with:

```bash
curl -sS -o <file> https://dc.g-vo.org/tap/sync \
  --data-urlencode "REQUEST=doQuery" --data-urlencode "LANG=ADQL" \
  --data-urlencode "FORMAT=votable" --data-urlencode "QUERY=<query>"
```

| File | Query | HTTP | Content-Type |
|---|---|---|---|
| `tap_schema_tables.xml` | `SELECT * FROM TAP_SCHEMA.tables WHERE schema_name = 'hipparcos'` | 200 | `application/x-votable+xml` |
| `tap_schema_columns.xml` | `SELECT * FROM TAP_SCHEMA.columns WHERE table_name = 'hipparcos.main'` | 200 | `application/x-votable+xml` |

Its tables have no `table_index`, and its columns add `sourceRD`.
