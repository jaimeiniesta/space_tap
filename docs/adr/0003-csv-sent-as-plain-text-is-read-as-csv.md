# CSV sent as plain text is read as CSV

TAP 1.1 §3.2 says "CSV data must be returned with a MIME type of text/csv", and `SpaceTAP.query/3` decides how to read a successful response from its Content-Type, never from its body. Two services break that rule: the NASA Exoplanet Archive and KOA, both run by IPAC, answer `FORMAT=csv` with CSV labelled `text/plain`. Their own `/capabilities` map the `csv` alias to `text/csv`, and asking for `text/csv` by name gets a 502, so no request parameter avoids it. SpaceTAP only asks for CSV, so it reads a 2xx `text/plain` response as CSV too. The Content-Type still decides: no other type is read as CSV, and the body is never inspected to guess its format.

## Considered Options

- Accept `text/csv` only and list the two services as known incompatibilities: the rule stays as the standard writes it, but SpaceTAP can't query either service until it reads VOTable results, which they label correctly.
- Read any 2xx body as CSV, whatever its Content-Type: an HTML page or a VOTable would also go to the CSV parser, and a service that doesn't support CSV (MAST answers with VOTable) would give a misleading CSV error or a bogus table instead of "expected text/csv".

## Consequences

A 2xx `text/plain` body that is not a result comes back as a table instead of a `:decode_error`: a single line such as `OK` becomes one column named `OK` with no rows. None has been seen: when the query is lost, both services answer with a VOTable error document and HTTP 400. Plain text with an error status is still an error, not a result (ADR 0004). Both services also send their IPAC table format as `text/plain`, but SpaceTAP never requests it; if a later version requests formats other than CSV, read `text/plain` as CSV only when CSV was requested.
