# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `format: :votable` in `SpaceTAP.query/3`, which asks the TAP service for VOTable and reads its rows in the serialization the service sends, TABLEDATA, BINARY or BINARY2, into typed values: integers, floats, booleans, strings and lists, with `nil` for a null cell or NaN. CSV stays the default.
- `SpaceTAP.Result` gains `fields`, a `SpaceTAP.Field` describing each column (name, datatype, arraysize, xtype, unit, UCD, utype, description and null value), and `overflow`, `true` when the service truncated the result. Both are `nil` for CSV.
- A livebook that runs the queries of the parity tests through SpaceTAP in Elixir cells and through PyVO in Python cells, with Pythonx, and compares the columns, the overflow and the value of every cell. It also shows the same row as SpaceTAP reads it from CSV and from VOTable, and as PyVO reads it.
- The README shows `format: :votable`, with the typed values, fields and overflow it gives, a Formats column in Compatibility, and a link to the PyVO livebook for those coming from Python.

### Changed

- A VOTable sent when CSV was requested, as MAST sends, is still a `:decode_error`, and its message now says to pass `format: :votable`.
- SpaceTAP reads XML with Saxy, a new dependency, instead of xmerl.
- A VOTable error document is a `:service_error` only when its `QUERY_STATUS` is directly inside the `RESOURCE` of type `results`, where DALI 1.1 §4.4 puts it, rather than anywhere in the document. Every service SpaceTAP has been checked against puts it there.
- MAST works with `format: :votable`, so the README no longer lists it as not working.
- The Pleiades livebook reads Gaia's VOTable, so its colour–magnitude diagram uses typed values instead of parsing strings. The getting-started livebook shows typed values and overflow, and the tour of TAP services queries MAST with `format: :votable`.

## [0.1.0] - 2026-10-28

### Added

- `SpaceTAP.query/3`, which runs a sync query: it POSTs the ADQL query to the `/sync` endpoint of a TAP service, asking for CSV, and returns the result, also when the service labels the CSV `text/plain`, as the NASA Exoplanet Archive does. Options: `:maxrec`, and `:req_options` for Req.
- `SpaceTAP.Result`, the table a query returns: its columns in order and its rows, with CSV values as strings and empty cells as `nil`.
- `SpaceTAP.Error`, the error a query returns: a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a message, and the HTTP status, which the exception message starts with. A service error comes from a VOTable error document, or from plain text with HTTP 400, as KOA and CADC send.
- A README with usage, errors, the limits of CSV results and the TAP services SpaceTAP has been checked against, and HexDocs with the SpaceTAP icon.
- Livebooks that run SpaceTAP against Gaia, GAVO, the NASA Exoplanet Archive and other TAP services, with tables and charts, each with a "Run in Livebook" button on HexDocs.

[Unreleased]: https://github.com/jaimeiniesta/space_tap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jaimeiniesta/space_tap/releases/tag/v0.1.0
