# to_dataframe takes the types of the fields

`SpaceTAP.Result.to_dataframe/1` turns a result into an Explorer data frame. Explorer is an optional dependency, which the function checks for when it is called. Each column of a VOTable result gets the dtype of its field's datatype, at the same width: a `float` is `{:f, 32}` and a `short` `{:s, 16}`. An array is a list, nested once for each dimension of its arraysize but the one a string takes. The column keeps its dtype even when every cell is null or there are no rows. astropy, which PyVO reads with, keeps the same widths. A `float` holds the exact value of its 32 bits (ADR 0007), so it fits `{:f, 32}` without loss, and it reaches Nx, whose floats are 32-bit by default, without a conversion. A CSV result has no fields, so its columns are strings (ADR 0006).

Explorer refuses two columns with the same name. A TAP service may send them for `SELECT a.ra, b.ra`: on 2026-11-18, 7 of the 9 services in the Compatibility table that answered did, and GAVO and MAST renamed the second one themselves. VizieR and SIMBAD didn't answer, as CDS was down. A repeated name gets a number after it, as PyVO names it: `ra2`, then `ra3`, or `ra22` when a column is already called `ra2`. `columns` keeps the names the service sent.

## Considered Options

- Implement `Table.Reader` for `SpaceTAP.Result`, as `adbc` does for its results, so that `Explorer.DataFrame.new/2`, `Kino.DataTable` and VegaLite read a result without SpaceTAP depending on Explorer. It adds `table` as a required dependency, and Explorer would infer the dtypes, `{:f, 64}` for a `float` and `{:s, 64}` for a `short`, unless the caller passes them. It can still be added later without breaking anything.
- Infer the dtypes of a CSV result from its text: an identifier with leading zeros would become an integer, and a column whose first rows are empty would be guessed wrong. The format decides the types (ADR 0006).
- Widen every integer to `{:s, 64}` and every float to `{:f, 64}`, as Explorer infers them from Elixir values: a `float` column would take twice the memory, and the dtypes would differ from astropy's.
- Rename a repeated name with an underscore, `ra_2`, as MAST does and as astropy does when it names columns by their `ID`: it reads better, but someone coming from PyVO would see other names, and the parity tests couldn't compare them.
- Refuse a result with a repeated name and ask for `AS` in the ADQL: every crossmatch that selects the same column from two tables would fail.
- Decide when SpaceTAP compiles whether Explorer is there, as `req_ch` does: adding Explorer to a project after SpaceTAP was compiled would then depend on Mix compiling SpaceTAP again.

## Consequences

The data frame has no units, UCDs or descriptions: they stay in `fields`, and the overflow in the result. The conversion starts from a result whose rows are already lists, so it lowers the memory a result keeps, not the peak while it is read. A renamed column has one name in the data frame and another in `columns`.

SpaceTAP asks for Explorer `~> 0.13`, the version CI tests. An optional dependency isn't installed for a project without it, but a project with it must meet the requirement, so one that pins Explorer below 0.13 has to update it to install SpaceTAP, even if it never calls `to_dataframe/1`. The tests of `to_dataframe/1` and the parity tests on the fixtures passed on 2026-11-18 with Explorer 0.8.3, 0.9.2, 0.10.1, 0.11.1 and 0.12.0. 0.8.0 failed on a null inside a column of nested lists, and 0.7.2 has no `{:u, 8}`. The requirement can go down to 0.8.3 without breaking anyone if someone needs it, while raising it later would break the projects that use an older Explorer.
