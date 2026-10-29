# SpaceTAP

SpaceTAP is an Elixir client for the IVOA Table Access Protocol: it sends ADQL queries to astronomical archives and reads back the tables they return.

## Language

### Services

**TAP**:
The IVOA Table Access Protocol, an HTTP protocol for querying the tables of astronomical archives.
_Avoid_: Test Anything Protocol (an unrelated protocol with the same acronym)

**DALI**:
The IVOA Data Access Layer Interface, the standard with the parts shared by all IVOA data access services. TAP 1.1 builds on DALI 1.1.

**TAP service**:
An archive's implementation of TAP, such as the Gaia archive.
_Avoid_: server, API, endpoint

**Service URL**:
The base URL of a TAP service, to which endpoint names such as `/sync` are appended. TAP 1.1 calls it the *access URL*.
_Avoid_: endpoint, sync URL

### Queries and results

**ADQL**:
The SQL-like query language of TAP. The TAP service parses and runs it; the client sends it as text.

**Sync query**:
A query whose result comes back in the response to the same HTTP request.

**Async query**:
A query the TAP service runs as a job, whose result the client fetches later.

**Result**:
The table a query returns: its columns, in order, and its rows.
_Avoid_: response, dataset, records

**MAXREC**:
The maximum number of rows the client asks the TAP service to return. The service may apply a lower limit of its own.

**Overflow**:
A result the TAP service truncated because it reached MAXREC or its own limit. Only VOTable can signal it.
_Avoid_: truncation (when naming the condition)

**VOTable**:
The IVOA XML format for tables, used for results and for error documents.

**Field**:
The description of one column of a VOTable: its name, datatype, arraysize, unit, UCD and other metadata.
_Avoid_: column metadata, column info

**Datatype**:
The primitive type of a field's values, one of the twelve VOTable defines, such as `int`, `double` or `char`. With the arraysize, it says how each value is written.
_Avoid_: type (alone, since a field also has an xtype)

**Xtype**:
An extended type that gives a field's values a meaning beyond their datatype, such as `timestamp` or `point` (DALI).

**Null**:
A cell with no value. VOTable marks it with an empty cell, a null flag, a declared null value, or NaN in a floating-point field.
_Avoid_: missing value

**Serialization**:
How a VOTable writes the rows of its table: TABLEDATA (one XML element per cell), BINARY or BINARY2 (packed binary in base64), or FITS. The TAP service chooses it.
_Avoid_: encoding (which names the character encoding of the document, or the base64 of a binary stream)

### Errors

**Error document**:
What a TAP service sends instead of a result when a query fails: a VOTable whose query status is `ERROR`, or plain text.

**Query status**:
The `QUERY_STATUS` value a TAP service puts in the results resource of a VOTable: `OK`, `ERROR` or `OVERFLOW`. A document may carry two, `OK` before the table and `ERROR` or `OVERFLOW` after it.

**Service error**:
A failure the TAP service reports in an error document, such as invalid ADQL or an unknown table.
_Avoid_: query error, API error
