# Read the serialization the service sends

A VOTable writes the rows of its table as TABLEDATA, BINARY, BINARY2 or FITS (VOTable 1.5 §5). The `serialization` parameter of its media type is the only way to ask for one (VOTable §8), and no IVOA standard makes a service honour it or support any particular serialization. On 29 October 2026, `FORMAT=votable` got TABLEDATA from the NASA Exoplanet Archive, IRSA, KOA, ESO, CADC and MAST, BINARY2 from Gaia, and BINARY from GAVO and NED. Asking for `RESPONSEFORMAT=application/x-votable+xml;serialization=TABLEDATA` changed nothing at Gaia, NED and MAST, got an `ERROR` document from IRSA and KOA, and a 502 from the NASA Exoplanet Archive, although DALI 1.1 §3.4.3 says the response to a media type with parameters "must be equivalent". So `format: :votable` sends `FORMAT=votable` alone (DALI §3.4.3), as CSV sends `FORMAT=csv`, and SpaceTAP reads TABLEDATA, BINARY and BINARY2, whichever arrives. It tells them apart by the child element of `DATA`, not by the Content-Type: GAVO sends BINARY with no `serialization` parameter. FITS, which no service sends unless asked, is a `:decode_error`.

## Considered Options

- Read TABLEDATA only and ask Gaia for `FORMAT=votable_plain`, an ESA value that gets TABLEDATA: SpaceTAP would need to know which service it is talking to, and GAVO and NED would still send BINARY. NED sends it even for its own `votable/td` alias.
- Ask for `serialization=TABLEDATA` and read TABLEDATA only: the three IPAC services reject the request, and Gaia, NED and MAST ignore it.
- Read TABLEDATA and BINARY2 only: Gaia works, GAVO and NED don't.

## Consequences

Each serialization needs tests with fixtures from a service that sends it. A value must come out the same whichever serialization carried it, so a query gives the same result from a service that changes its default. A service that starts sending FITS gets a `:decode_error` until SpaceTAP reads it.
