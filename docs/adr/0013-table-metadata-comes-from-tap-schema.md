# Table metadata comes from TAP_SCHEMA

`SpaceTAP.tables/2` and `SpaceTAP.columns/3` read the tables and the columns a TAP service publishes from `TAP_SCHEMA`, with a sync query in VOTable, and not from the VOSI `/tables` resource. Every TAP service must have `TAP_SCHEMA` (TAP 1.1 §4, TAP 1.0 §2.6), while `/tables` is only a "should" (TAP 1.1 §2.5). On 2026-11-18 the 9 services in the Compatibility table that answered had it, with as many tables as `/tables` listed; VizieR and SIMBAD didn't answer, as CDS was down. The query asks for `SELECT *`, and each value is read by its standard name in lower case, since ADQL names are case insensitive (ADQL 2.1 §2.1.7). A service that lacks a standard column gives `nil`, and the columns a service adds are left out. The rows are sorted by `table_index` or `column_index` in SpaceTAP, the ones without one last. VOTable rather than CSV because MAST sends only VOTable, and because it gives the flags `indexed`, `principal` and `std` as integers, which become booleans.

A result marked as overflow (DALI 1.1 §4.4.1) gives its list with a warning in the log. The grill first chose an error, since a list cut short without notice is wrong, but MAST marks every result as overflow, even with `MAXREC=100000` or with no rows, so `tables/2` and `columns/3` would never have worked there.

## Considered Options

- Read `/tables`: on 2026-11-18 only GAVO honoured `detail=min`. IRSA, CADC and MAST never sent columns, and Gaia, the NASA Exoplanet Archive, NED, KOA and ESO always did, up to 2.6 MB. The per-table resource returned the whole document at four services and 404 at ESO. Gaia's root element is in another namespace, and KOA's columns aren't valid against the schema.
- Name the columns of TAP 1.1 in the `SELECT`: NED has no `arraysize` or `xtype`, as in TAP 1.0, so the query would fail there.
- Sort with `ORDER BY table_index`: TAP 1.0 has no such column.
- Return a `SpaceTAP.Result` of the query rather than structs: the names and the set of columns would change from one service to another, and from TAP 1.0 to 1.1.
- An `:overflow` error, as first chosen: it makes both functions useless at MAST.
- Ignore the overflow: a list cut short at VizieR, which has more than 27,000 catalogues, would pass unnoticed.

## Consequences

SpaceTAP logs for the first time, and does so at every call to MAST. `datatype` holds whatever the service writes, a VOTable datatype from TAP 1.1 or an ADQL type such as `BIGINT` from TAP 1.0, and `arraysize` the text of the service, `"1"` from IRSA for a single value.
