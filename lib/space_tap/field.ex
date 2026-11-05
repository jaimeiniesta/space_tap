defmodule SpaceTAP.Field do
  @moduledoc """
  The description of one column of a VOTable result, read from its `FIELD`
  element (VOTable 1.5 §4).

  The `datatype` and the `arraysize` say how each value is written, and so
  which Elixir value a cell becomes. The other attributes say what the values
  mean, and come as the service wrote them: SpaceTAP doesn't interpret them, so
  a field with the `timestamp` xtype still holds strings.
  """

  @enforce_keys [:name, :datatype]
  defstruct [:name, :datatype, :arraysize, :xtype, :unit, :ucd, :utype, :description, :null]

  @typedoc """
  One of the twelve primitive datatypes of VOTable 1.5 §2.1, written as in
  the standard.

  A cell of an integer datatype (`:unsignedByte`, `:short`, `:int`, `:long`)
  is an integer, one of `:float` or `:double` a float, one of `:boolean` a
  boolean, and one of `:char` or `:unicodeChar` a string. A float cell holding
  NaN is `nil`, and one holding an infinity is `:infinity` or `:neg_infinity`,
  since a BEAM float can be neither. SpaceTAP doesn't read the cells of
  `:bit`, `:floatComplex` and `:doubleComplex` fields.
  """
  @type datatype ::
          :boolean
          | :bit
          | :unsignedByte
          | :short
          | :int
          | :long
          | :char
          | :unicodeChar
          | :float
          | :double
          | :floatComplex
          | :doubleComplex

  @typedoc """
  The description of a column:

    * `:name` - the name of the column, as in the `columns` of the result.
    * `:datatype` - the primitive type of the values.
    * `:arraysize` - `nil` when each cell holds one value. Otherwise, the
      dimensions of the array in each cell, as the service wrote them: `"3"`,
      `"100*"` (up to 100), `"*"` (any number) or `"64x64x10*"`, whose first
      dimension changes fastest (§2.2). A cell with an array is a list, and
      one with a multidimensional array a list of lists. A string is an array
      of characters, so it comes as one string.
    * `:xtype` - the extended type, such as `"timestamp"` or `"point"`, which
      gives the values a meaning beyond their datatype (§4.3).
    * `:unit` - the unit of the values, such as `"deg"` or `"mas/yr"` (§4.4).
    * `:ucd` - the Unified Content Descriptor, which says what the values
      measure, such as `"pos.eq.ra;meta.main"` (§4.5).
    * `:utype` - the place of the column in a data model (§4.6).
    * `:description` - the text of the `DESCRIPTION` element.
    * `:null` - the `null` attribute of the `VALUES` element (§4.7): the value
      that marks a cell with no data, as the service wrote it. Those cells are
      already `nil`.
  """
  @type t :: %__MODULE__{
          name: String.t(),
          datatype: datatype(),
          arraysize: String.t() | nil,
          xtype: String.t() | nil,
          unit: String.t() | nil,
          ucd: String.t() | nil,
          utype: String.t() | nil,
          description: String.t() | nil,
          null: String.t() | nil
        }
end
