# AGENTS.md

Instructions for AI coding agents working on this repository.

## What this is

SpaceTAP is an Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol astronomical archives use to expose tabular data. Queries are written in ADQL and results come back as VOTable (or CSV and other formats).

This is not the Test Anything Protocol. Keep that in mind when searching for references or naming things.

Specifications:

- TAP 1.1: https://www.ivoa.net/documents/TAP/20190927/REC-TAP-1.1.html
- Related IVOA standards: DALI, UWS (async jobs), VOTable, ADQL.

We target TAP 1.1 and stay compatible with TAP 1.0 services. When a behaviour comes from the spec, cite the section in code comments or docs.

Name things with the terms defined in `GLOSSARY.md`. Decisions with their reasoning and rejected options are recorded as ADRs in `docs/adr/`.

## Scope

Stick to the scope of the version being worked on. If an idea belongs to a later version, suggest it instead of implementing it.

## Working on this project

- Work in small steps. For anything larger than a small change, propose a plan before writing code.
- Explain the reasoning behind design decisions and point to the relevant part of the spec.
- Ask before adding dependencies, committing, pushing, tagging or publishing to Hex.
- Code, docs, README, CHANGELOG and commit messages are in English.

## Design decisions already made

- Public entry point: `SpaceTAP.query(service_url, adql, opts)`, returning `{:ok, %SpaceTAP.Result{columns: [...], rows: [...]}}` or `{:error, %SpaceTAP.Error{}}`. A struct rather than a list of maps, so column order is kept and conversion to dataframes is easy.
- Errors: one exception, `%SpaceTAP.Error{type, message, status}`, with types `:service_error`, `:http_error`, `:transport_error` and `:decode_error`. The response body decides the type before the HTTP status (`docs/adr/0001-one-error-struct-with-a-type.md`).
- `service_url` is the base URL of the service, the TAP 1.1 §2.4 access URL. Trim trailing `/`s and append `/sync`, treating every `service_url` as a base URL, even one that already ends in `/sync`.
- Sync queries POST `REQUEST=doQuery`, `LANG=ADQL` and `FORMAT=csv`. `REQUEST` is required by TAP 1.0 (§2.3.1), and a TAP 1.1 service must ignore it (§2.7). `FORMAT` goes alone and in lowercase: TAP 1.1 services must accept it as equivalent to `RESPONSEFORMAT`, sending both is undefined (§2.7.3), and parameter values are case sensitive (DALI §3.1).
- Options: `:maxrec` maps to `MAXREC` and takes a non-negative integer; `0` is sent and returns the columns with no rows (DALI 1.1 §3.4.4). `:req_options` is merged into `Req.new/1`: tests inject `plug: {Req.Test, SpaceTAP}` through it, and users raise Req's default 15 s `receive_timeout` with it (long queries belong to async, 0.3). SpaceTAP's own Req options win the merge, including `decode_body: false`, `http_errors: :return` and `into: nil`, which keep the `{:ok, _}`/`{:error, _}` contract; any other option, such as `:headers`, goes to Req as given. Unknown options raise `ArgumentError` via `Keyword.validate!/2`, and so does a `:req_options` that isn't a keyword list. No application config.
- Most services send error documents as VOTable even when CSV was requested. The error message is the trimmed content of the last `INFO name="QUERY_STATUS"` element, or a message of SpaceTAP's own when that content is empty, since it is optional (DALI §4.4, §4.4.2); services add other `INFO`s, so find it by name. KOA and CADC send plain text with HTTP 400, which is a `:service_error` too; plain text with any other error status is an `:http_error`, because a proxy may have written it (`docs/adr/0004-plain-text-with-400-is-a-service-error.md`).
- Parse XML with `:xmerl_sax_parser` and `disallow_entities`. `:xmerl_scan` would turn element and attribute names into atoms, and SAX is the shape VOTable TABLEDATA parsing needs in 0.2.
- CSV: the first row is always the header, whatever the `header=` media-type parameter says (TAP 1.1 §3.2). An empty cell becomes `nil`: no spec defines NULL in CSV, and Gaia sends an empty field. A 2xx `text/plain` response is read as CSV too, because the NASA Exoplanet Archive and KOA label CSV that way; no other type is (`docs/adr/0003-csv-sent-as-plain-text-is-read-as-csv.md`).
- The client is stateless. No GenServer or supervision tree: async UWS jobs live on the TAP service, and waiting for one is polling with backoff in the caller's process.
- No Ecto-style query builder. Small ADQL helpers (cone search, value escaping) are planned for a later version.

Agreed dependencies: `req` and `nimble_csv`, plus `credo` (`only: [:dev, :test], runtime: false`) and `ex_doc` (`only: :dev, runtime: false`) for development, and `plug` (`only: :test`), which `Req.Test` needs. `dialyxir` comes in 0.2, and `explorer` later as an optional dependency. Discuss any other dependency before adding it.

## Code and tests

- Use `mix format`. Public functions get `@spec`, and those of documented modules get `@doc`; internal modules (`@moduledoc false`) explain themselves in comments. Public types get `@typedoc`. Add doctests when they don't need the network.
- Unit tests use `Req.Test` stubs and never touch the network.
- Integration tests hit real services, are tagged `@tag :integration` and are excluded by default in `test/test_helper.exs`. Run them with `mix test --include integration`. The default target is the Gaia archive (`https://gea.esac.esa.int/tap-server/tap`). Keep those queries small (`TOP 5` or similar) to be polite to the service.
- Services tests send the queries of each service's fixtures to the other services in the README's Compatibility table and check that they still answer the same way. They are tagged `:services`, excluded by default and run with `mix test.services`. A failure there is a reason to look into that service, not a release blocker, so `mix test.release` leaves them out. When a service changes how it answers, capture its fixture again and update both tests; a SpaceTAP bug it reveals gets its own issue.
- Parity tests run the same queries through SpaceTAP and through PyVO (an Astropy-affiliated Python client for IVOA services, used as reference implementation) against live services, and compare the results. Those for Gaia and the NASA Exoplanet Archive are tagged `@tag :pyvo`, excluded by default, and run with `mix test --only pyvo` and `mix test.release`; those for the other services that send CSV are tagged `:services` and run with `mix test.services`, so an outage at one of them doesn't hold a release. Both read their services and queries from `test/support`, shared with the services tests. They call a PEP 723 script through `uv run`, which pins PyVO and prints JSON; without `uv` they skip locally and fail when `CI` is set. Until SpaceTAP parses VOTable with types (0.2), they compare column names and row counts; after that, values too.
- CI runs the lint checks and unit tests only. Run integration and parity tests locally before a release.
- Before saying a change is done, run `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test` and `mix docs --warnings-as-errors`, and report the results.
- After changing dependencies, run `mix hex.audit` to check that none has been retired.
- Keep `CHANGELOG.md` up to date following Keep a Changelog.

## Contributions made with AI tools

AI-assisted contributions are welcome, but a human must open, supervise and answer for every issue and pull request. Don't open issues or pull requests on your own.
