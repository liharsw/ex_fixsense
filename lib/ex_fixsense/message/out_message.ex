defmodule ExFixsense.Message.OutMessage do
  @moduledoc """
  Struct representing an outgoing FIX message.

  This struct is used with the fluent `ExFixsense.Message.Builder` API
  to construct FIX messages in a readable, chainable way.

  ## Fields

  - `:msg_type` - FIX message type (Tag 35), e.g., "D" for New Order Single
  - `:fields` - Ordered list of {tag, value} tuples for the message body (preserves insertion order)

  ## Examples

      # Create a new message
      msg = %OutMessage{msg_type: "D", fields: []}

      # Typically created via Builder
      msg = ExFixsense.Message.Builder.new("D")

  ## Message Types (Common)

  - `"D"` - New Order Single
  - `"V"` - Market Data Request
  - `"x"` - Security List Request
  - `"AN"` - Request for Positions
  - `"H"` - Order Status Request
  - `"G"` - Order Cancel Request
  - `"F"` - Order Cancel/Replace Request

  ## See Also

  - `ExFixsense.Message.Builder` - Fluent API for building messages
  """

  @type t :: %__MODULE__{
          msg_type: String.t(),
          fields: [{String.t(), String.t() | [String.t()]}]
        }

  @enforce_keys [:msg_type]
  defstruct [:msg_type, fields: []]
end
