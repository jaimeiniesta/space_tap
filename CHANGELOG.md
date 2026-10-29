# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A livebook that runs the queries of the parity tests through SpaceTAP in Elixir cells and through PyVO in Python cells, with Pythonx, and compares the results. It also shows the same row as each client reads it, and the overflow that PyVO reads and CSV can't carry.

## [0.1.0] - 2026-10-28

### Added

- `SpaceTAP.query/3`, which runs a sync query: it POSTs the ADQL query to the `/sync` endpoint of a TAP service, asking for CSV, and returns the result, also when the service labels the CSV `text/plain`, as the NASA Exoplanet Archive does. Options: `:maxrec`, and `:req_options` for Req.
- `SpaceTAP.Result`, the table a query returns: its columns in order and its rows, with CSV values as strings and empty cells as `nil`.
- `SpaceTAP.Error`, the error a query returns: a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a message, and the HTTP status, which the exception message starts with. A service error comes from a VOTable error document, or from plain text with HTTP 400, as KOA and CADC send.
- A README with usage, errors, the limits of CSV results and the TAP services SpaceTAP has been checked against, and HexDocs with the SpaceTAP icon.
- Livebooks that run SpaceTAP against Gaia, GAVO, the NASA Exoplanet Archive and other TAP services, with tables and charts, each with a "Run in Livebook" button on HexDocs.

[Unreleased]: https://github.com/jaimeiniesta/space_tap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jaimeiniesta/space_tap/releases/tag/v0.1.0
