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

The error document is VOTable 1.5 and starts with an `xml-stylesheet`
processing instruction and no XML declaration, which xmerl misreads as a broken
declaration (see `SpaceTAP.VOTable`).
