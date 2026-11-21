# async_query/3 starts, waits for and deletes a job

TAP 1.1 runs an async query as a UWS job that lives on the service (§2.2), and each of the nine services SpaceTAP was checked against on 16 and 17 November 2026 implements UWS a little differently. `SpaceTAP.Job` has the steps of a job, and `SpaceTAP.async_query/3`, built from them alone, submits a job, waits for it in the caller's process, reads its result and deletes the job:

- **Submit.** POST the query to `/async` without `PHASE=RUN`, which GAVO, ESO and CADC ignore there, and read the job at the URL of the 303, where the redirects end: the NASA Exoplanet Archive gives an `http://` URL, which it redirects to `https://`, and which since 0.4.1 is read with `https://` from the start, by the rule of ADR 0015. Send `PHASE=RUN` only to a PENDING job, the one phase a client may change (DALI 1.1 §2.1), and read the job at its URL again, since the Gaia archive redirects that request to `<job>/phase`. A job created but not read or started is deleted, since the error doesn't give its URL.
- **Wait.** `GET <job>?WAIT=30` (UWS 1.1 §2.2.1.2), never `-1`: something in front of GAVO cuts the connection after about 120 seconds. When the service answers before the 30 seconds with the same phase, as the Gaia archive and IRSA do, pause before asking again, from 1 second up to 30, 1.5 times longer each time. Stop at a phase the job won't leave without the client: COMPLETED, ERROR, ABORTED, ARCHIVED, PENDING or HELD (UWS 1.1 §2.1.3). `:timeout` is `:infinity` by default.
- **Read.** The result is at the href of the `result` whose id is `result` in the job document, since "a client must always parse the Results List" (UWS 1.1 §2.2.2.3): CADC lists others, such as `diag`, and its result is on another host. A result is never read over `http://` for a job at an `https://` URL: GAVO lists `http://` URLs on its own host, read with `https://`. Credentials don't go to another host, as Req keeps them from a redirect that leaves the host. A job that stopped in another phase than COMPLETED is a `:service_error` with the message of its error summary.
- **Delete.** DELETE the job without following its 303 to the list of jobs, which held 682 jobs at GAVO, and POST `ACTION=DELETE` when DELETE fails, as it does at NED (403), KOA (500) and the NASA Exoplanet Archive (502) (UWS 1.1 §2.2.3.2). `async_query/3` deletes the job whatever happens, and returns its result or error even when the delete fails.

## Considered Options

- `PHASE=RUN` in the request that creates the job, which UWS 1.1 §2.2.3.1 shows as an example: one request fewer where it works, but GAVO, ESO and CADC leave the job PENDING.
- PyVO's wait, `WAIT=-1` and a pause after every answer: `-1` meets GAVO's cut, and the pause delays the news of a phase change from a service that blocks.
- A finite default `:timeout`: `async_query/3` deletes the job when it runs out, so a default would stop jobs the service was going to finish. Services limit how long a job runs, from 60 seconds at the Gaia archive, ESO and NED to 4 hours at CADC, but not how long it waits in their queue, which is what a caller who wants a bound sets `:timeout` for.
- `<job>/results/result`, the name TAP 1.1 §2.2 gives the result: KOA serves it as `text/plain`, which ADR 0003 reads as CSV, where its href serves `text/xml`.
- The `/error` resource for the message: it isn't a VOTable at the NASA Exoplanet Archive, holds a stack trace at NED and is on another host at CADC. PyVO reads the error summary too.
- A `delete: false` option for `async_query/3`: it returns no job URL, so a kept job would be out of reach. The steps in `SpaceTAP.Job` keep a job, and the option can be added later without breaking anything.
- A process per job: the job's state lives on the service, and its URL is all a client needs to follow it.

## Consequences

- The NASA Exoplanet Archive, KOA and IRSA answer a delete with success and keep the job until its destruction time, which IRSA doesn't set.
- A job whose caller dies while it waits stays on the service until its destruction time too.
- A service that ignores `WAIT` is asked again within 30 seconds of a change of phase, at most.
