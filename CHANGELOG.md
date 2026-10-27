# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A README with usage, errors and the limits of CSV results, and HexDocs with the SpaceTAP icon.
- `mix test.all`, which runs the unit, Gaia integration and Gaia/pyvo parity suites together.
- Live parity tests that compare SpaceTAP with pyvo against the Gaia archive for a Pleiades query and positive `MAXREC`.
- `SpaceTAP.Result`, the table a query returns: its columns in order and its rows, with CSV values as strings and empty cells as `nil`.
- `SpaceTAP.query/3`, which runs a sync query: it POSTs the ADQL query to the `/sync` endpoint of a TAP service, asking for CSV, and returns the result. Options: `:maxrec`, and `:req_options` for Req.
- Integration tests against the Gaia archive for successful queries, service errors and `MAXREC`.
- `SpaceTAP.Error`, the error a query returns: a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a message, and the HTTP status, which the exception message starts with.
