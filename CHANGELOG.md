# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The README opens with what SpaceTAP does, when to use it and how to get started: the first query, the same one with `format: :votable`, and a table of what to read next. The notes it had on the base URL and on `http://` redirects stay in the docs of `SpaceTAP.query/3` and in the Compatibility table.

### Fixed

- The getting-started livebook said the Gaia archive at ESA answers its query on `gaia.dr3lite`, a table only GAVO has. ESA's table is `gaiadr3.gaia_source`.

## [0.4.1] - 2026-11-22

### Added

- `SpaceTAP.Job` has `given_url`, the URL the client gave, the service URL for `submit/3` and the job URL for `get/2`, which every request about the job keeps the credentials of its `:req_options` with: a job on another host, scheme or port, also one the service's own redirects led to, gets neither the `authorization` header nor Req's `:auth` option from `submit/3`, `wait/2`, `result/2` or `delete/2`.

### Changed

- SpaceTAP sends each request once: it sets Req's `retry: false` unless `:req_options` sets `:retry` (`docs/adr/0016-each-request-is-sent-once.md`). Before, Req retried a `GET` that failed with a 408, 429, 500, 502, 503 or 504, or with a transport timeout, three times with a growing delay, waiting as long as a `Retry-After` header said, so `SpaceTAP.availability/2` at a service in maintenance answered seconds or minutes later, and `SpaceTAP.Job.wait/2` could run past its `:timeout` and return the service's error instead of `:timeout`.
- `SpaceTAP.Job.wait/2` asks without `WAIT` when less than a second of its `:timeout` is left, where it sent `WAIT=0`, since `WAIT` takes the seconds to block for and none were left.
- A VOTable result is read with what each `FIELD` says about its cells, the shape of its `arraysize`, its `null` value and the bytes of an element, read once per field where it was read for every cell: a BINARY2 result of 100,000 rows reads about 10 % faster, and the `null` value of a field is parsed once rather than once per cell.
- The `:decode_error` of `SpaceTAP.tables/2` and `SpaceTAP.columns/3` for a result without the column they read, or with a flag that isn't 0 or 1, has `status: nil`: it is about the result, not the response, whose 200 it carried.

### Fixed

- `SpaceTAP.Job.submit/3` reads the job the service's 303 points to as `SpaceTAP.Job.result/2` reads a result and `SpaceTAP.availability/2` an availability, by the one rule for every URL a service lists (`docs/adr/0015-listed-urls-are-read-by-one-rule.md`): an `http://` job URL on the service's host, as the NASA Exoplanet Archive answers, is read with `https://`, and a job on another host, scheme or port gets neither the `authorization` header nor Req's `:auth` option, in the requests of `submit/3` that read, start and delete it, nor in those of `wait/2`, `result/2` and `delete/2`, so `SpaceTAP.async_query/3` sends none either, and none of them does after a redirect of the job itself to another host, scheme or port. Before, the first request to the job went to the URL as given, with the credentials, which at the NASA Exoplanet Archive meant over `http://`, and Req dropped them on the redirect to `https://`, so the job was read without them. An `http://` job on another host is a `:decode_error`, and stays on the service.
- `SpaceTAP.Job.submit/3` doesn't read or delete the list of jobs when the 303 points there, as it does with an empty `Location` or with the service's host in another case: that is an `:http_error`, since a `POST` to delete at the list would create a job.
- A URL a service lists with a scheme other than `http` or `https`, or with user information in it, which RFC 9110 §4.2.4 tells a recipient to treat as an error, is a `:decode_error` and isn't read. The first reached Req, which raised `ArgumentError`, and in `SpaceTAP.async_query/3` the job then wasn't deleted; the second was sent as Basic auth.
- Options that aren't a keyword list, such as a map, raise `ArgumentError` as an unknown option does, where they raised `FunctionClauseError`.
- A VOTable, a job document or a VOSI document cut inside a comment or a processing instruction before the root element, or holding a byte there that isn't UTF-8, is a `:decode_error`. Saxy 1.7 raises `CaseClauseError` on it instead of returning the error, and the raise reached the caller of `SpaceTAP.query/3` and of every other function: GAVO's documents begin with such a processing instruction, and MAST's with a comment.
- An integer of more than 20 characters in a cell, an array element, a `VALUES null` or an `arraysize`, and an `arraysize` of more than 16 dimensions, are a `:decode_error`. `Integer.parse/1` took millions of digits and raised `SystemLimitError` beyond them, and nesting an array cost the elements times the dimensions.
- A CSV body that begins with a UTF-8 byte order mark is read without it, as the XML readers read theirs. The mark stayed in the first column's name.
- An attribute is read by its name before its local name, so an `xsi:type` next to the `type` of a `RESOURCE` no longer stands in for it; the local name still finds `xlink:href`.
- An availability capability without an `accessURL`, or with a blank one, is a `:decode_error` that says so, where `SpaceTAP.availability/2` read `/capabilities` again as the availability. A job document whose result `href` is blank lists no result.
- `SpaceTAP.ADQL.literal/1` raises `ArgumentError` for an improper list, such as `[1 | 2]`, as for any value ADQL has no literal for, where it raised `FunctionClauseError`.
- The host of a URL a service lists is compared with the service's without regard to case (RFC 3986 §3.2.2), so `http://TAP.example.org/...` from `https://tap.example.org` is read with `https://` too.
- `SpaceTAP.availability/2` resolves a relative availability URL against the URL the redirects to `/capabilities` led to, the base of the document (RFC 3986 §5.1.3), rather than against the URL it asked.
- A VOTable, a job document or a VOSI document that begins with a UTF-8 byte order mark, which XML 1.0 §4.3.3 allows, is read. It was a `:decode_error`, since Saxy doesn't take the mark. No known service sends one.
- A `char` string of more than 64 bytes read from a BINARY or BINARY2 stream is a binary of its own. It was a reference into the decoded stream, which it kept in memory, all of it, for as long as the string lived, as when a caller keeps one description of a result and drops the rest.
- A CSV body that is a blank line, or starts with one, is a `:decode_error`, since it has no header row with the column names (TAP 1.1 §3.2). It was a result with one column named `""`.
- The README of the livebooks said they install `{:space_tap, "~> 0.1.0"}`; they install `~> 0.4.0`.
- The logo of the README loads from GitHub, so hex.pm shows it: hex.pm renders the README from the package, which doesn't hold `assets/`.
- The docs of `SpaceTAP.Error` say that plain text is an `:http_error` with an error status other than 400, not with any status, since with a 2xx it is read as CSV, and when a `:decode_error` has `status: nil`; the example of `SpaceTAP.Job` lists its result with `https://`, as GAVO does since November 2026.

## [0.4.0] - 2026-11-21

### Added

- `SpaceTAP.Result.to_dataframe/1`, which turns a result into an `Explorer.DataFrame`. Explorer is an optional dependency: add `{:explorer, "~> 0.13"}` to use it. Each column of a VOTable result gets the dtype of its field at the same width, such as `{:f, 32}` for a `float`, and an array a list; every column of a CSV result is a string. A column name the service repeats gets a number after it, `ra2`, as in PyVO (`docs/adr/0011-to-dataframe-takes-the-types-of-the-fields.md`).
- `SpaceTAP.ADQL`, which writes ADQL text: `literal/1` writes a string, a number, `nil` or a list for `IN` as an ADQL literal, doubling the single quotes of a string, and `cone/5` writes the condition of a cone search with `CONTAINS`, `POINT` and `CIRCLE` in ICRS, a form services with ADQL 2.0 and with ADQL 2.1 both take (`docs/adr/0012-adql-helpers-write-plain-text.md`).
- `SpaceTAP.tables/2` and `SpaceTAP.columns/3`, which list the tables a TAP service publishes, as `SpaceTAP.Table` structs, and the columns of one, as `SpaceTAP.Column` structs, from its `TAP_SCHEMA`, in the order the service recommends. `tables/2` takes `:schema` to list one schema. A value the service doesn't give is `nil`, and a list the service marks as overflow comes with a warning in the log, since MAST marks every result so (`docs/adr/0013-table-metadata-comes-from-tap-schema.md`).
- `SpaceTAP.availability/2`, which asks a TAP service whether it is available and returns a `SpaceTAP.Availability`, with the times and notes the service gives. It finds the availability through the service's capabilities, as GAVO lists it outside its service URL, and reads it with `https://` when the service lists it with `http://` on its own host. A service that says it isn't available gives `{:ok, _}` with `available: false`, whatever the HTTP status (`docs/adr/0014-availability-is-found-through-capabilities.md`).
- The README's Compatibility table has Tables and Availability columns, with what each service does differently: GAVO lists its availability outside its service URL, NED's `TAP_SCHEMA` follows TAP 1.0, KOA sends its VOSI documents with no `Content-Type`, MAST marks every result as overflow, even one with no rows, and `tables/2` fails at the Gaia archive, whose `TAP_SCHEMA.tables` has descriptions that aren't ASCII and answers any `WHERE` with HTTP 500.
- The README has sections on data frames, tables and columns, writing ADQL and availability, and the Installation section names Explorer for data frames.
- The livebooks turn results into data frames: the Pleiades, GAVO and NASA Exoplanet Archive livebooks compute with Explorer instead of lists of maps, the GAVO one lists tables and columns with `tables/2` and `columns/3` and writes a value with `ADQL.literal/1`, and the getting-started livebook has a section on data frames.

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

[Unreleased]: https://github.com/jaimeiniesta/space_tap/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/jaimeiniesta/space_tap/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/jaimeiniesta/space_tap/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jaimeiniesta/space_tap/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/jaimeiniesta/space_tap/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/jaimeiniesta/space_tap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jaimeiniesta/space_tap/releases/tag/v0.1.0
