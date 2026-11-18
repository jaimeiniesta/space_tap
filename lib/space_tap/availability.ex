defmodule SpaceTAP.Availability do
  @moduledoc """
  Whether a TAP service says it is available, from its VOSI availability
  document (VOSI 1.1 §3.2). `SpaceTAP.availability/2` returns it.

  It is what the service says about itself: a service that doesn't answer
  at all gives a `:transport_error` instead, and one that says it is
  available may still fail a query.
  """

  @enforce_keys [:available]
  defstruct [:available, :up_since, :down_at, :back_at, notes: []]

  @typedoc """
  The availability of a service:

    * `:available` - whether the service is accepting requests.
    * `:up_since` - when it last became available.
    * `:down_at` - when it will next go down.
    * `:back_at` - when it will be back, if it is down.
    * `:notes` - what else the service says, in its words.

  The times come as the service writes them, an `xsd:dateTime` such as
  `"2026-10-30T12:22:56Z"`, or `nil` when it doesn't give them.
  """
  @type t :: %__MODULE__{
          available: boolean(),
          up_since: String.t() | nil,
          down_at: String.t() | nil,
          back_at: String.t() | nil,
          notes: [String.t()]
        }
end
