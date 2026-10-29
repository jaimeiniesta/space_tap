# How VOTable values map to Elixir

VOTable gives each field one of twelve datatypes (VOTable 1.5 §2.1), and SpaceTAP turns each cell into an Elixir value: an integer for `unsignedByte`, `short`, `int` and `long`, a float for `float` and `double`, a boolean, a string for `char` and `unicodeChar`, and a list for an array, nested for a multidimensional one (§2.2). Where BEAM floats or a serialization fall short, SpaceTAP picks a value every serialization can produce, so a cell comes out the same whichever serialization carried it (ADR 0005):

- NaN is `nil`. BINARY has no other way to mark a null float, VOTable §5.5 doesn't require telling NaN from null, and a BEAM float can't be NaN. astropy masks NaN too.
- +Inf and -Inf are `:infinity` and `:neg_infinity`, the atoms Explorer uses, since a BEAM float can't be infinite either.
- A `float` is the exact value of its 32 bits, also when TABLEDATA writes it as text: `3.6157947` in TABLEDATA and the same four bytes in BINARY2 both give `3.6157946586608887`, as PyVO does.
- A null, an empty cell and a zero-length string or array are all `nil`. TABLEDATA can't tell them apart (§5.5), and BINARY has no null flag, so NED sends its null strings empty. Only BINARY2 could keep an empty string.
- The xtype is not interpreted (§4.3), so a `timestamp` stays a string. An astronomical time never carries a time zone (DALI 1.1 §3.3.3), and its time scale, such as TT or TDB, is declared in a `TIMESYS` element (VOTable §3.5): a UTC `DateTime` would misstate it.

## Considered Options

- NaN as an atom such as `:nan`: a null `double` from NED would differ from a null `double` from Gaia.
- A `float` as the shortest decimal that gives back the same 32 bits, `3.6157947`: it reads better, but Erlang only has that algorithm for 64-bit floats, and parity with PyVO would need a tolerance.
- Each serialization read on its own terms, such as TABLEDATA text parsed as a 64-bit float or `""` from BINARY2: a query would give different values when a service changes its default serialization.
- Timestamps as `DateTime`: wrong for every time scale but UTC.

## Consequences

Code that does arithmetic on a float column has to handle `nil`, `:infinity` and `:neg_infinity`, which `Float` functions don't accept. A `float` shows more digits than the service wrote. An empty string sent in BINARY2 comes back as `nil`.
