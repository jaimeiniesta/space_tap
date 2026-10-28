# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Livebooks in `livebooks/` that run SpaceTAP against Gaia, GAVO, the NASA Exoplanet Archive and other TAP services, with tables and charts.
- A README with usage, errors and the limits of CSV results, and HexDocs with the SpaceTAP icon.
- `mix test.all`, which runs the unit, Gaia integration and Gaia/pyvo parity suites together.
- Live parity tests that compare SpaceTAP with pyvo against the Gaia archive for a Pleiades query and positive `MAXREC`.
- `SpaceTAP.Result`, the table a query returns: its columns in order and its rows, with CSV values as strings and empty cells as `nil`.
- `SpaceTAP.query/3`, which runs a sync query: it POSTs the ADQL query to the `/sync` endpoint of a TAP service, asking for CSV, and returns the result, also when the service labels the CSV `text/plain`, as the NASA Exoplanet Archive does. Options: `:maxrec`, and `:req_options` for Req.
- Integration tests against the Gaia archive for successful queries, service errors and `MAXREC`.
- `mix test.services`, which sends the queries of the fixtures to the other services in the README's Compatibility table and checks that they still answer the same way.
- `SpaceTAP.Error`, the error a query returns: a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a message, and the HTTP status, which the exception message starts with. A service error comes from a VOTable error document, or from plain text with HTTP 400, as KOA and CADC send.
