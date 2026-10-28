---
status: superseded by ADR-0004
---

# Plain text is an HTTP error, not a service error

DALI 1.1 §4.2 lets a TAP service send its error document as a VOTable or as plain text, but only the VOTable shows that the service wrote it: its last query status is `ERROR` (DALI §4.4). Plain text looks the same when a proxy or web server in front of the service writes it, such as a 503 "upstream connect error" or a 404 for a mistyped service URL. So `SpaceTAP.query/3` returns a `:service_error` only for a VOTable error document, and plain text with an HTTP error status is an `:http_error` whose message is the text. pyvo does the same: it takes the text as the message and raises the `DALServiceError` it raises for any other HTTP error.

## Considered Options

- Plain text with any error status is a service error, as DALI allows: a proxy outage or a wrong URL would look like the service rejecting the query, and code that retries on `:http_error` would not retry it.
- Only plain text with a 4xx status is a service error: proxy 5xx pages become HTTP errors, but a mistyped URL (404) and an authenticating proxy (401, 403) would still look like service errors.

## Consequences

A TAP service that reports query errors in plain text gets an `:http_error` with its message instead of a `:service_error`. None has been seen so far (Gaia sends VOTable error documents); if one turns up, the rule can be narrowed for it. After 0.1.0, changing the rule changes the `:type` that callers match on.
