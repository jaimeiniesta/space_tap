# Plain text with HTTP 400 is a service error

DALI 1.1 §4.2 lets a TAP service send its error document as a VOTable or as plain text. A VOTable shows that the service wrote it, since its last query status is `ERROR` (DALI §4.4), so it is a `:service_error` whatever the HTTP status. Plain text doesn't: a proxy or web server in front of the service writes it too, such as a 503 "upstream connect error" or a 404 for a mistyped service URL. ADR 0002 made all plain text with an error status an `:http_error`, to be narrowed if a TAP service reported query errors that way. Two do: KOA and CADC answer invalid ADQL with HTTP 400 and the message as plain text (issue #17). A 400 says the server won't process the request because of a client error (RFC 9110 §15.5.1), and all that changes between SpaceTAP's requests is the query and `MAXREC`, so plain text with a 400 is a `:service_error` whose message is the text. Plain text with any other error status is still an `:http_error`. This supersedes ADR 0002.

## Considered Options

- Keep ADR 0002 and list both services in the README's Compatibility notes: no special case, but their query errors would be `:http_error`s, and code that retries on `:http_error` would retry a query that can never succeed.
- Plain text with any 4xx status is a service error: a 404 for a mistyped service URL and a 401 or 403 from an authenticating proxy would look like the service rejecting the query.
- Also unquote CADC's message, which comes as a single CSV field because CSV was requested: SpaceTAP would have to guess from the body that it is CSV, while it reads every response by its Content-Type (ADR 0003).

## Consequences

A plain-text 400 written by a proxy or web server comes back as a `:service_error`. None has been seen so far. CADC's message keeps its CSV quoting, and an empty plain-text 400 gets SpaceTAP's own message, as a VOTable error document without one does. PyVO raises the `DALServiceError` it raises for any HTTP error, so for these two services SpaceTAP's error type no longer matches PyVO's.
