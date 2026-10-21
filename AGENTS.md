# AGENTS.md

Instructions for AI coding agents working on this repository.

## What this is

SpaceTAP is an Elixir client for the IVOA Table Access Protocol (TAP), the HTTP protocol astronomical archives use to expose tabular data. Queries are written in ADQL and results come back as VOTable (or CSV and other formats).

This is not the Test Anything Protocol. Keep that in mind when searching for references or naming things.

Specifications:

- TAP 1.1: https://www.ivoa.net/documents/TAP/20190927/REC-TAP-1.1.html
- Related IVOA standards: DALI, UWS (async jobs), VOTable, ADQL.

We target TAP 1.1 and stay compatible with TAP 1.0 services. When a behaviour comes from the spec, cite the section in code comments or docs.

## Scope

Stick to the scope of the version being worked on. If an idea belongs to a later version, suggest it instead of implementing it.

## Working on this project

- Work in small steps. For anything larger than a small change, propose a plan before writing code.
- Explain the reasoning behind design decisions and point to the relevant part of the spec.
- Ask before adding dependencies, committing, pushing, tagging or publishing to Hex.
- Code, docs, README, CHANGELOG and commit messages are in English.

## Design decisions already made

- Public entry point: `SpaceTAP.query(service_url, adql, opts)`, returning `{:ok, %SpaceTAP.Result{columns: [...], rows: [...]}}` or `{:error, reason}`. A struct rather than a list of maps, so column order is kept and conversion to dataframes is easy.
- Sync queries POST to `<service_url>/sync` with `REQUEST=doQuery` (required by TAP 1.0, removed in 1.1, sent always for compatibility), `LANG=ADQL` and `FORMAT=csv`. Option `:maxrec` maps to `MAXREC`.
- Services return errors as VOTable documents (`INFO name="QUERY_STATUS" value="ERROR"`) even when CSV was requested. Parse them with `:xmerl` from OTP.
- The client is stateless. No GenServer or supervision tree: async UWS jobs live on the server, and waiting for one is polling with backoff in the caller's process.
- No Ecto-style query builder. Small ADQL helpers (cone search, value escaping) are planned for a later version.
- The shape of `reason` in error tuples is not decided yet. Propose options before implementing it.

Agreed dependencies: `req` and `nimble_csv`, plus `credo` for development (`only: [:dev, :test], runtime: false`). `explorer` will come later as an optional dependency. `dialyxir` may be added once the first public functions have specs. Discuss any other dependency before adding it.

## Code and tests

- Use `mix format`. Public functions get `@doc` and `@spec`. Add doctests when they don't need the network.
- Unit tests use `Req.Test` stubs and never touch the network.
- Integration tests hit real services, are tagged `@tag :integration` and are excluded by default in `test/test_helper.exs`. Run them with `mix test --include integration`. The default target is the Gaia archive (`https://gea.esac.esa.int/tap-server/tap`). Keep those queries small (`TOP 5` or similar) to be polite to the service.
- Parity tests run the same queries through SpaceTAP and through pyvo (the IVOA client for Python, used as reference implementation) against live services, and compare the results. They are tagged `@tag :pyvo`, excluded by default, and run with `mix test --only pyvo`. They need a Python environment with pyvo (Docker or `uv`, to be decided when implemented). Until SpaceTAP parses VOTable with types (0.2), they compare column names and row counts; after that, values too.
- Before saying a change is done, run `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` and `mix test`, and report the results.
- After changing dependencies, run `mix hex.audit` to check that none has been retired.
- Keep `CHANGELOG.md` up to date following Keep a Changelog.

## Contributions made with AI tools

AI-assisted contributions are welcome, but a human must open, supervise and answer for every issue and pull request. Don't open issues or pull requests on your own.
