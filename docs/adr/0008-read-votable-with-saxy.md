# Read VOTable with Saxy

SpaceTAP 0.1 reads error documents with `:xmerl_sax_parser`, which comes with OTP. A VOTable result is much larger: 100,000 rows and six columns of Gaia DR3 make 5.6 MB in BINARY2 and 18.2 MB in TABLEDATA. The criterion was fixed before measuring: Saxy replaces xmerl only if it halves the median parse time or the peak memory on either file, where the peak counts everything the reading process holds, the document included. `bench/xmerl_vs_saxy.exs` read both files with each parser feeding the same collector, on 5 November 2026 (Apple M1, OTP 28.1.1, Elixir 1.20.3, the median of five runs for time and three for memory, each run in a fresh process):

| File      | Measure     | xmerl     | Saxy     | xmerl/Saxy |
|-----------|-------------|-----------|----------|------------|
| BINARY2   | median time | 563.7 ms  | 10.9 ms  | 51.6       |
| BINARY2   | peak memory | 267.2 MB  | 16.7 MB  | 16.0       |
| TABLEDATA | median time | 1735.5 ms | 875.1 ms | 1.98       |
| TABLEDATA | peak memory | 85.6 MB   | 86.2 MB  | 0.99       |

Saxy halves both on BINARY2, so it replaces xmerl. Almost all of the difference comes from the `STREAM`: BINARY2 carries its rows as one base64 text node, which xmerl hands over as a charlist, one 16-byte list cell per character, while Saxy hands over a binary that points into the document. The files come from the copy of Gaia DR3 at ARI Heidelberg, because the ESA archive was too overloaded to answer that day; they hold the same rows. Saxy 1.7.0 has no runtime dependencies and no native code.

## Considered Options

- Keep xmerl, with no dependency at all. TABLEDATA, which six of the nine services probed for ADR 0005 send, comes just short of the threshold (1.98). But Gaia, SpaceTAP's main target, sends BINARY2, and reading its results with xmerl would take about 50 times the time and 16 times the memory.

## Consequences

- Saxy doesn't expand entities declared in a DTD, internal or external: it leaves the reference as text, so a `&lol;` cell reaches `parse_text/2` as those five characters. That keeps the protection `disallow_entities` gave against entity expansion, without an error for the document.
- Saxy reads a document that starts with an `xml-stylesheet` processing instruction and has no XML declaration, which xmerl rejects (issue #10), so the declaration SpaceTAP prepends for xmerl can go.
- Saxy leaves a namespace prefix on element names, so SpaceTAP matches the local name.
- With Saxy, turning cell text into values costs about as much as parsing the XML: `parse_text/2` takes 929 ms on the 600,000 cells of the TABLEDATA file. Reading each field's `arraysize` and `null` once, rather than in every cell, is where the next gain is.
