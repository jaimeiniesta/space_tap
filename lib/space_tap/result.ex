defmodule SpaceTAP.Result do
  @moduledoc """
  The table a query returns: its columns, in order, and its rows.

  Each row is a list with one value per column, in the same order as
  `columns`. What the values are depends on the format the query asks for
  with the `:format` option of `SpaceTAP.query/3`:

    * CSV, the default, carries no types, so every value is a string and an
      empty cell is `nil`: no IVOA standard defines how CSV represents NULL.
      CSV can't carry `fields` or `overflow`, so both are `nil`.
    * VOTable describes each column with a `SpaceTAP.Field`, whose datatype
      decides the value of each cell: an integer, a float, a boolean, a
      string, or a list for an array. A null cell is `nil`, and so is a float
      holding NaN; +Inf and -Inf are `:infinity` and `:neg_infinity`.
      `overflow` is `true` when the TAP service truncated the result at
      MAXREC or at a limit of its own (DALI 1.1 §4.4.1).
  """

  @enforce_keys [:columns, :rows]
  defstruct [:columns, :rows, :fields, :overflow]

  @typedoc """
  The value of a cell: a string or `nil` from CSV, and any of these from
  VOTable, as the datatype and arraysize of its field say.
  """
  @type value ::
          String.t()
          | integer()
          | float()
          | boolean()
          | :infinity
          | :neg_infinity
          | nil
          | [value()]

  @typedoc """
  A result:

    * `:columns` - the column names, in order.
    * `:rows` - one list of values per row.
    * `:fields` - the description of each column, in order, from VOTable.
      `nil` from CSV.
    * `:overflow` - whether the TAP service truncated the result, from
      VOTable. `nil` from CSV.
  """
  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[value()]],
          fields: [SpaceTAP.Field.t()] | nil,
          overflow: boolean() | nil
        }
end
