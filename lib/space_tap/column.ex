defmodule SpaceTAP.Column do
  @moduledoc """
  A column of a table a TAP service publishes, as its `TAP_SCHEMA.columns`
  describes it (TAP 1.1 §4.3). `SpaceTAP.columns/3` returns them.

  It describes a column you can query. The columns of a result are
  described by `SpaceTAP.Field`, from the VOTable the query returns.
  """

  @enforce_keys [:name]
  defstruct [
    :name,
    :datatype,
    :arraysize,
    :xtype,
    :unit,
    :ucd,
    :utype,
    :description,
    :indexed,
    :principal,
    :std
  ]

  @typedoc """
  A column of a table of a TAP service:

    * `:name` - the name to use in a query, with the double quotes of a
      name that needs them.
    * `:datatype` - its type as the service writes it: a VOTable datatype
      such as `"double"` from a TAP 1.1 service, and an ADQL type such as
      `"DOUBLE"` or `"adql:VARCHAR"` from a TAP 1.0 one.
    * `:arraysize` - the size of its arrays, as in VOTable, such as `"*"`.
      Services write `nil` or `"1"` for a single value.
    * `:xtype` - its extended type, such as `"timestamp"`.
    * `:unit` - the unit of its values, such as `"deg"`.
    * `:ucd` - what its values measure, such as `"pos.eq.ra;meta.main"`.
    * `:utype` - its place in a data model.
    * `:description` - what it holds, in the service's words.
    * `:indexed` - whether the service keeps an index on it, so that a
      condition on it runs fast.
    * `:principal` - whether the service counts it as a core part of the
      table, to show by default.
    * `:std` - whether a standard defines it, as ObsCore defines the
      columns of `ivoa.ObsCore`.

  A value the service doesn't give is `nil`: TAP 1.0 services have no
  `:arraysize` or `:xtype`.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          datatype: String.t() | nil,
          arraysize: String.t() | nil,
          xtype: String.t() | nil,
          unit: String.t() | nil,
          ucd: String.t() | nil,
          utype: String.t() | nil,
          description: String.t() | nil,
          indexed: boolean() | nil,
          principal: boolean() | nil,
          std: boolean() | nil
        }
end
