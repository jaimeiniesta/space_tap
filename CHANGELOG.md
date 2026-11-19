# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `SpaceTAP.Result.to_dataframe/1`, which turns a result into an `Explorer.DataFrame`. Explorer is an optional dependency: add `{:explorer, "~> 0.13"}` to use it. Each column of a VOTable result gets the dtype of its field at the same width, such as `{:f, 32}` for a `float`, and an array a list; every column of a CSV result is a string. A column name the service repeats gets a number after it, `ra2`, as in PyVO (`docs/adr/0011-to-dataframe-takes-the-types-of-the-fields.md`).
- `SpaceTAP.ADQL`, which writes ADQL text: `literal/1` writes a string, a number, `nil` or a list for `IN` as an ADQL literal, doubling the single quotes of a string, and `cone/5` writes the condition of a cone search with `CONTAINS`, `POINT` and `CIRCLE` in ICRS, a form services with ADQL 2.0 and with ADQL 2.1 both take (`docs/adr/0012-adql-helpers-write-plain-text.md`).
- `SpaceTAP.tables/2` and `SpaceTAP.columns/3`, which list the tables a TAP service publishes, as `SpaceTAP.Table` structs, and the columns of one, as `SpaceTAP.Column` structs, from its `TAP_SCHEMA`, in the order the service recommends. `tables/2` takes `:schema` to list one schema. A value the service doesn't give is `nil`, and a list the service marks as overflow comes with a warning in the log, since MAST marks every result so (`docs/adr/0013-table-metadata-comes-from-tap-schema.md`).
- `SpaceTAP.availability/2`, which asks a TAP service whether it is available and returns a `SpaceTAP.Availability`, with the times and notes the service gives. It finds the availability through the service's capabilities, as GAVO lists it outside its service URL, and reads it with `https://` when the service lists it with `http://` on its own host. A service that says it isn't available gives `{:ok, _}` with `available: false`, whatever the HTTP status (`docs/adr/0014-availability-is-found-through-capabilities.md`).
- The README's Compatibility table has Tables and Availability columns, with what each service does differently: GAVO lists its availability outside its service URL, NED's `TAP_SCHEMA` follows TAP 1.0, KOA sends its VOSI documents with no `Content-Type`, and MAST marks every result as overflow, even one with no rows.
- The README has sections on data frames, tables and columns, writing ADQL and availability, and the Installation section names Explorer for data frames.

## [0.3.0] - 2026-11-18

### Added

- `SpaceTAP.async_query/3`, which runs a query as a job: it submits the job, waits for it, reads its result as `query/3` reads a sync one, and deletes the job whatever happens. It takes the options of `query/3` and a `:timeout`. A job that stops in another phase than COMPLETED, such as ERROR or ABORTED, is a `:service_error` with the service's message (`docs/adr/0010-async-query-starts-waits-for-and-deletes-a-job.md`).
- `SpaceTAP.Job`, the steps of an async query, which a TAP service runs as a job (TAP 1.1 §2.2): `submit/3` creates a job and starts it, and deletes it if it can't, `wait/2` waits for it to stop, `result/2` reads its result, `get/2` reads a job from its URL, and `delete/2` deletes it. A `SpaceTAP.Job` holds the URL of the job, its phase, the format of its result, the message the service gives when it fails, and the URL of its result.
- `wait/2` asks the service to answer when the phase of the job changes, with the `WAIT` parameter of UWS 1.1, and pauses between requests to a service that answers at once instead. Its `:timeout` option, `:infinity` by default, gives a new error type, `:timeout`, when it runs out.
- `result/2` never reads a result over `http://` for a job at an `https://` URL, and doesn't send the `authorization` header or Req's `:auth` to a result on another host.
- The README's Compatibility table has an Async column, with what each service does differently with jobs: the Gaia archive stops an anonymous user's job after 60 seconds, IRSA labels the CSV result of a job as VOTable, MAST sends CSV for a job, and the NASA Exoplanet Archive, KOA and IRSA keep a job they answer they have deleted.
- The README has an Async queries section, with `async_query/3` and the steps of `SpaceTAP.Job`, and the getting-started livebook runs a query as a job, one step at a time.

## [0.2.1] - 2026-11-16

### Changed

- SpaceTAP reads TABLEDATA results about a third faster, 1.9 s instead of 2.9 s for 100,000 rows of six columns, and reads every value as before.
- A `FIELD` after the `DATA` of its `TABLE`, where VOTable 1.5 §3.8 puts the `DATA` last, is a `:decode_error` that says so. Before, the error was about the number of cells in a row, and a table with no rows gave none.
- The README notes that KOA applies `TOP` before `ORDER BY`, as the NASA Exoplanet Archive does, and that the Gaia archive at ESA sends `parallax` as a 64-bit `double`, with more digits than in GAVO's copy of Gaia DR3.

## [0.2.0] - 2026-11-16

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
- The README's examples and the livebooks that read Gaia DR3 query its copy at the GAVO Data Center, the service releases are tested against (`docs/adr/0009-gavo-is-the-service-releases-are-tested-against.md`). The README notes that the Gaia archive at ESA answers the same queries.
- The Pleiades livebook reads VOTable, so its colour–magnitude diagram uses typed values instead of parsing strings. The getting-started livebook shows typed values and overflow, and the tour of TAP services queries MAST with `format: :votable`.

## [0.1.0] - 2026-10-28

### Added

- `SpaceTAP.query/3`, which runs a sync query: it POSTs the ADQL query to the `/sync` endpoint of a TAP service, asking for CSV, and returns the result, also when the service labels the CSV `text/plain`, as the NASA Exoplanet Archive does. Options: `:maxrec`, and `:req_options` for Req.
- `SpaceTAP.Result`, the table a query returns: its columns in order and its rows, with CSV values as strings and empty cells as `nil`.
- `SpaceTAP.Error`, the error a query returns: a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a message, and the HTTP status, which the exception message starts with. A service error comes from a VOTable error document, or from plain text with HTTP 400, as KOA and CADC send.
- A README with usage, errors, the limits of CSV results and the TAP services SpaceTAP has been checked against, and HexDocs with the SpaceTAP icon.
- Livebooks that run SpaceTAP against Gaia, GAVO, the NASA Exoplanet Archive and other TAP services, with tables and charts, each with a "Run in Livebook" button on HexDocs.

[Unreleased]: https://github.com/jaimeiniesta/space_tap/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/jaimeiniesta/space_tap/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/jaimeiniesta/space_tap/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jaimeiniesta/space_tap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jaimeiniesta/space_tap/releases/tag/v0.1.0
