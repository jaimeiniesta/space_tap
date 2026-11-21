# Listed URLs are read by one rule

A TAP service gives the client three URLs to read next: the job URL, in the 303 that answers the query that creates a job (UWS 1.1 §2.2.3.1), the result URL, in the job document (UWS 1.1 §2.2.2.3), and the availability URL, in the capabilities (DALI 1.1 §2.4). None of the specs says anything about the scheme or the host of those URLs, and the services differ: the NASA Exoplanet Archive answers with an `http://` job URL on its own host, which it redirects to `https://`, GAVO lists its availability over `http://` and outside its service URL, and CADC lists the result of a job on another host. SpaceTAP reads every listed URL by one rule, in `SpaceTAP.HTTP.listed/4`: never over `http://` after `https://`, so an `http://` URL on the host of the URL the client gave is read with `https://`, which those services serve, and one on another host is a `:decode_error` and isn't read; and the credentials, the `authorization` header and Req's `:auth` option, stay with the scheme, host and port of the URL the client gave, as Req keeps them from a redirect that leaves them. The hosts are compared without regard to case (RFC 3986 §3.2.2).

Until 0.4.0 the rule applied to the result and to the availability (ADR 0010 and 0014), and `SpaceTAP.Job.submit/3` read the job at the URL of the 303 as given. At the NASA Exoplanet Archive, the first request to the job went over `http://` with the credentials, and Req then dropped them on the redirect to `https://`, so the job was read without them. A job on another host got the credentials in the requests that read, start and delete it.

## Considered Options

- Follow the 303 with Req's redirect step, with its `:redirect_trusted` off: Req drops the credentials when the redirect changes the scheme, host or port, but only on the request that follows it, after the first one has gone over `http://`. And the 303 isn't followed on purpose, so that SpaceTAP knows the job's URL even when reading or starting it fails and it must be deleted.
- Delete a job the rule won't read, the `http://` one on another host: the delete would go over `http://` too, which is what the rule forbids. The job stays on the service, named in the error, until the service destroys it.
- Treat a 303 whose `Location` is the list of jobs, as an empty one resolves to, as a job: reading it fails, and deleting it would be a request to the list, where a POST creates a job. It is an `:http_error`, like a redirect that isn't a 303.

## Consequences

- `SpaceTAP.Job.submit/3`, `SpaceTAP.Job.result/2` and `SpaceTAP.availability/2` describe the rule the same way, and a change to it is made once.
- `SpaceTAP.availability/2` resolves a relative availability URL against the URL the redirects to `/capabilities` led to, the base of the document it read (RFC 3986 §5.1.3), while the rule starts from the service URL, which is where the credentials belong.
