# Each request is sent once

SpaceTAP sends each request to a TAP service once: `SpaceTAP.HTTP.run/2` sets Req's `retry: false` unless the caller's `:req_options` set `:retry`. Req's default, `retry: :safe_transient`, retries a `GET` or `HEAD` that gets a 408, 429, 500, 502, 503 or 504, or a transport timeout, three times, after 1, 2 and 4 seconds, and waits as long as a `Retry-After` header says on a 429 or a 503. SpaceTAP inherited it without deciding, and none of its docs mentioned it: `SpaceTAP.availability/2` at a service that answered its availability with a 503 and `Retry-After: 2` took 6 seconds to return the document, and a service in maintenance may ask for an hour; `SpaceTAP.Job.wait/2` with a `:timeout` of a second at a service answering 503 took 6.6 seconds and returned the `:http_error` rather than `:timeout`, and at a service that didn't answer four times its `:receive_timeout`. A `POST`, which a sync query and the creation of a job are, was never retried, since it isn't a safe method (RFC 9110 §9.2.1).

## Considered Options

- Keep Req's default and document it: the delays stay, and a `Retry-After` of a service in maintenance decides how long `availability/2` takes, which is the question it was asked.
- Turn retries off only where they hurt, in `availability/2`, whose 503 is the answer, and in the polls of `wait/2`, which retries itself, and keep Req's default elsewhere: more to explain, and the request for the result of `async_query/3` could still sleep on a `Retry-After`.
- Retries of SpaceTAP's own: a policy for every service, when none of them has asked for one.

## Consequences

- A transient error on the request for the result of `SpaceTAP.async_query/3` fails the query, after the job has run, and `async_query/3` deletes the job. `req_options: [retry: :safe_transient]` gives Req's behaviour back, with its `Retry-After` waits.
- `SpaceTAP.Job.wait/2` keeps to its `:timeout` within one request, and returns the error of a request that fails at once.
- Setting `:retry` is the one way to retry: `:max_retries` or `:retry_delay` alone, with `retry: false`, retry nothing.
