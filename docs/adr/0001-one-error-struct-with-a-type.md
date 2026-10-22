# One error struct with a type

`SpaceTAP.query/3` returns `{:error, %SpaceTAP.Error{}}`, a single exception with a `:type` (`:service_error`, `:http_error`, `:transport_error` or `:decode_error`), a `:message`, and the HTTP `:status` when there was a response. Being an exception gives `Exception.message/1` for free and lets a later `query!/3` raise it unchanged. One module with a `:type` field keeps pattern matching simple (`%SpaceTAP.Error{type: :service_error}`). Transport failures are wrapped rather than returning `Req.TransportError`, so the public contract does not depend on the HTTP client.

## Considered Options

- Tagged tuples such as `{:service_error, message}`: no message protocol, and a `query!/3` would have to build an exception anyway.
- One exception module per kind of error: more modules for the same pattern-matching power.

## Consequences

The type comes from the response body before the HTTP status: an error document is a `:service_error` whatever the status, because TAP 1.1 §3.3 lets services report errors with 200 as well as 4xx or 5xx codes. Gaia, for example, answers invalid ADQL with HTTP 400 and a VOTable error document, even when CSV was requested.
