# ADQL helpers write plain text

ADQL has no bound parameters: a value goes into a query as text, and a string with a single quote in it, or a float Elixir writes with a lowercase `e`, has to be written the way ADQL 2.1 §2.1.8 reads it. `SpaceTAP.ADQL` has two functions that return that text and nothing else. `literal/1` writes a string, a number, `nil` or a list for `IN`, and raises for a value ADQL has no literal for, such as an infinity or a boolean. `cone/5` writes the condition of a cone search as `CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', ra, dec, radius)) = 1`. On 2026-11-18 the 9 services in the Compatibility table that answered declared `CONTAINS`, `POINT` and `CIRCLE`; VizieR and SIMBAD didn't answer, as CDS was down. Four of them, the NASA Exoplanet Archive, KOA, CADC and MAST, didn't declare `DISTANCE`, the form ADQL 2.1 §4.2.7 prefers. Most of them declared only ADQL 2.0, which requires the coordinate system that ADQL 2.1 deprecates (§4.2.5).

## Considered Options

- A sigil that escapes what it interpolates, as the roadmap suggested with `~ADQL`: since Elixir 1.15 a sigil of more than one letter must be uppercase, and uppercase sigils don't interpolate. A one-letter sigil such as `~q` would take a short name that another library may import too. A macro that wraps each `#{}` in `literal/1` would hide the escaping from whoever reads the query.
- `DISTANCE(POINT(ra, dec), POINT(ra0, dec0)) <= radius`, as ADQL 2.1 §4.2.7 recommends: four services in the Compatibility table don't declare it, and the 2.0 form needs a coordinate system as well.
- Pick the form from what the service declares in its capabilities (TAPRegExt): writing a query would then need a request to the service.
- An option for the coordinate system: NED accepted `'ICRS'` and `'J2000'` alike on 2026-11-18, and an option can be added without breaking anything.
- Write `true` and `false` as `1` and `0`: ADQL 2.1 has no boolean literal, so the meaning would be SpaceTAP's guess.

## Consequences

The functions don't check the query, and the columns of `cone/5` are inserted as given, so they must never come from user input. There is still no query builder.
