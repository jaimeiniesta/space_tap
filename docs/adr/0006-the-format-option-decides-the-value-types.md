# The format option decides the value types

`SpaceTAP.query/3` asks for CSV by default and for VOTable with `format: :votable`. CSV carries no types, so its values are strings; VOTable gives each field a datatype, so its values are integers, floats, booleans and strings. MAST answers `FORMAT=csv` with a VOTable, which TAP 1.1 §2.7.3 allows: VOTable is required, CSV only recommended. SpaceTAP can read that VOTable, but doesn't when CSV was requested: the response is a `:decode_error` whose message points to `format: :votable`. The same call with the same options gives values of the same types whichever service answers, so code written against one service keeps working against another.

## Considered Options

- Read the VOTable and return typed values: the call that gives strings from Gaia would give integers and floats from MAST, and code that parses the strings would fail only against MAST.
- Read the VOTable and pass on each value as text, as CSV would: only TABLEDATA has text to pass on, so a service that sends a binary serialization would get numbers turned back into text the service never wrote.

## Consequences

MAST, which never sends CSV, needs `format: :votable`, and the README's Compatibility table says so. Following ADR 0003, a 2xx `text/plain` response is read as CSV only when CSV was requested; with `format: :votable` it is a `:decode_error`.
