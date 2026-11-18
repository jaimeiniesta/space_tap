defmodule SpaceTAP.Table do
  @moduledoc """
  A table a TAP service publishes, as its `TAP_SCHEMA.tables` describes it
  (TAP 1.1 §4.2). `SpaceTAP.tables/2` returns them, and
  `SpaceTAP.columns/3` the columns of one.

  It describes a table you can query, not the result of a query, which is a
  `SpaceTAP.Result`.
  """

  @enforce_keys [:name]
  defstruct [:schema, :name, :type, :description, :utype]

  @typedoc """
  A table of a TAP service:

    * `:name` - the name to use in a query, which may include the schema,
      as in `"gaiadr3.gaia_source"`, and the double quotes of a name that
      needs them, as in `~s("I/239/hip_main")`.
    * `:schema` - the name of the schema that holds it.
    * `:type` - `"table"` or `"view"`, or another type the service names.
    * `:description` - what it holds, in the service's words.
    * `:utype` - its place in a data model, such as `"ivo://ivoa.net/std/ObsCore#table-1.1"`.

  A value the service doesn't give is `nil`.
  """
  @type t :: %__MODULE__{
          schema: String.t() | nil,
          name: String.t(),
          type: String.t() | nil,
          description: String.t() | nil,
          utype: String.t() | nil
        }
end
