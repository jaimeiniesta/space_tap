# Livebooks

[Livebook](https://livebook.dev) notebooks that run SpaceTAP against real TAP
services, with tables and charts.

| Notebook | What it shows |
|---|---|
| [Getting started](getting_started.livemd) | A first query, the result, options and errors. |
| [The Pleiades with Gaia](gaia_pleiades.livemd) | Cluster members picked by proper motion, their colour–magnitude diagram and the distance to the cluster. |
| [GAVO Data Center](gavo.livemd) | `TAP_SCHEMA`, the naked-eye sky and the nearest stars from Hipparcos, a search of the IVOA Registry, and DaCHS error documents. |
| [NASA Exoplanet Archive](nasa_exoplanet_archive.livemd) | Discoveries by method and year, planets by period and radius, and a service that applies `TOP` before `ORDER BY`. |
| [A tour of TAP services](tap_services_tour.livemd) | One query against eleven services at once, and every kind of error. |

## Running them

Open a notebook from this folder in Livebook. Each one installs SpaceTAP from
this checkout with `{:space_tap, path: Path.join(__DIR__, "..")}`, so it runs the
code you have, plus [Kino](https://hexdocs.pm/kino) for tables and
[Kino VegaLite](https://hexdocs.pm/kino_vega_lite) for charts.

Every query goes to a live service, so results change as the archives do, and a
service may be slow or down. The queries are small, to be polite to the
services.
