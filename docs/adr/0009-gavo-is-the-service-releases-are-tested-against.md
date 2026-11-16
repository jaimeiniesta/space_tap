# GAVO is the service releases are tested against

`mix test.release` runs integration and parity tests against a live service, and a release waits for them to pass. Until 0.2.0 that service was the Gaia archive at ESA, SpaceTAP's main example. It failed on three days in two weeks: overloaded on 5 November 2026, and down on 15 and 16 November, which held the 0.2.0 release. In the same weeks CDS (VizieR and SIMBAD) didn't answer on 28 and 29 October and on 15 and 16 November, the NASA Exoplanet Archive answered with a maintenance page on 10 November, IRSA's proxy failed on 15 and 16 November, and NED didn't connect on 9 November. GAVO Data Center answered in every run of the services tests and the livebooks since 27 October.

So releases are tested against GAVO, on `gaia.dr3lite`, its copy of Gaia DR3: the Pleiades query of the README gives the same five stars there as at ESA, in the same order. Gaia and the NASA Exoplanet Archive join the services tests, which also run before a release, but whose failures don't hold it.

## Considered Options

- Keep the Gaia archive at ESA. It is where Gaia's data comes from, and the only service in the Compatibility table that sends BINARY2, but its outages decide when SpaceTAP can be released.
- The copy of Gaia DR3 at ARI Heidelberg, which holds all of `gaiadr3.gaia_source`. It answered when ESA didn't, but SpaceTAP has used it on three days only, and it is in Heidelberg too, at the same Zentrum für Astronomie as GAVO, so the two may fail together.
- Several services, all of which must pass. Each one added is one more that can be down on the day of a release.
- MAST, which hasn't failed either. Its tables aren't Gaia's, so the examples in the README and the livebooks would need other queries and other data.

## Consequences

- The live tests that hold a release read BINARY, which GAVO sends, and no longer BINARY2. Gaia's BINARY2 stays covered by its fixtures, read with values from astropy, and by Gaia's services tests.
- `gaia.dr3lite` declares `parallax` a `float`, where Gaia's archive has a `double`, and has neither `designation` nor `bp_rp`, which a query computes as `phot_bp_mean_mag - phot_rp_mean_mag`.
- GAVO sends one row more than MAXREC asks for, and one row with `MAXREC=0`, with an overflow indicator, although DALI 1.1 §3.4.4 says the service "must only return the requested number of rows". SpaceTAP returns the rows the service sends. The integration tests assert what GAVO sends, so they fail if it starts following §3.4.4, and SpaceTAP's own part, sending `MAXREC` and reading the overflow indicator, stays covered by unit tests.
- DaCHS, GAVO's software, sends error documents with HTTP 500, so the integration tests' service error comes with that status.
