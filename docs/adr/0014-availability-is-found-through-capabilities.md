# Availability is found through capabilities

`SpaceTAP.availability/2` reads the capabilities of the service at `<service URL>/capabilities`, where DALI 1.1 §2.5 puts them, and takes the URL of the availability from the access URL of the `ivo://ivoa.net/std/VOSI#availability` capability. TAP 1.1 §2 and DALI 1.1 §2 let a service put its availability anywhere, and GAVO lists it at `http://dc.g-vo.org/__system__/tap/run/availability`, outside its service URL. An `http://` URL on the host of an `https://` service is read with `https://`, which GAVO serves, and one on another host is a `:decode_error`; credentials stay with the service's host, as in `SpaceTAP.Job.result/2`. Both documents are read as XML when their media type is XML and also when they have none, since KOA sends them with no `Content-Type`; any other type is still an error. An availability document is the answer whatever the HTTP status it comes with, since the body decides before the status (ADR 0001), so `available: false` with a 503 is `{:ok, _}`.

## Considered Options

- Read `<service URL>/availability`, the fixed path of TAP 1.0: on 2026-11-18, 7 of the 9 services in the Compatibility table that answered served it there, but GAVO doesn't, and TAP 1.1 leaves the name to each service.
- Try `<service URL>/availability` when the capabilities list no availability: DALI 1.1 §2.4 requires them to list it, the 9 services did, and the fallback could read a page that isn't the service's availability.
- Return the capabilities with a public `capabilities/1`: it would model a whole TAPRegExt document, and it can be added later without breaking anything.
- Read only bodies with an XML media type, as for results: KOA's availability would never be read. As with plain text read as CSV (ADR 0003), the leniency is for a service that needs it, and applies to these two documents only.
- Make `available: false`, or a 503, an error: the document answers the question it was asked.

## Consequences

Each call makes two requests. The availability is what the service says about itself: a host that doesn't answer gives a `:transport_error`, as CDS gave on 2026-11-18, and a service that says it is available may still fail a query, so watching a service needs a small query as well.
