defmodule SpaceTAP.Result do
  @moduledoc """
  The table a query returns: its columns, in order, and its rows.

  Each row is a list with one value per column, in the same order as
  `columns`. Results read from CSV hold every value as a string, and an
  empty cell as `nil`: CSV carries no types, and no IVOA standard defines
  how it represents NULL.
  """

  @enforce_keys [:columns, :rows]
  defstruct [:columns, :rows]

  @type t :: %__MODULE__{
          columns: [String.t()],
          rows: [[String.t() | nil]]
        }
end
