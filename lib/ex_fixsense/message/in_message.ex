defmodule ExFixsense.Message.InMessage do
  @moduledoc """
  Minimal structure representing an incoming FIX message.

  InMessage contains only what's needed for message validation and routing,
  without opinionated field extraction or type conversion.

  ## Philosophy

  Unlike rich domain objects, InMessage is intentionally minimal:
  - Keeps raw binary for reference
  - Stores fields as list of tuples (not pre-parsed map)
  - Message type as string (not converted to atom)
  - Validation metadata (valid, complete, poss_dup)
  - No pre-extracted fields (symbol, cl_ord_id, etc.)
  - No automatic DateTime parsing

  ## Structure

  ```elixir
  %InMessage{
    msg_type: "8",                              # String (e.g., "D", "8", "W")
    seqnum: 42,                                 # Integer sequence number
    fields: [{"35", "8"}, {"55", "BTC-USD"}],   # List of {tag, value} tuples
    original_fix_msg: <<...>>,                  # Binary (raw FIX message)
    valid: true,                                # Boolean (validation result)
    complete: true,                             # Boolean (parse complete?)
    poss_dup: false,                            # Boolean (PossDupFlag set?)
    error_reason: nil,                          # Nil or error term
    subject: nil,                               # Nil (for custom routing)
    other_msgs: "",                             # String (buffered messages)
    rest_msg: ""                                # String (incomplete remainder)
  }
  ```

  ## Usage

  ### Access Fields
  ```elixir
  # Get specific field value
  symbol = msg.fields |> List.keyfind("55", 0) |> elem(1)

  # Or convert to map when needed
  field_map = msg.fields |> Map.new()
  symbol = field_map["55"]
  ```

  ### Check Message Type
  ```elixir
  case msg.msg_type do
    "D" -> handle_new_order(msg)
    "8" -> handle_execution_report(msg)
    "W" -> handle_market_data(msg)
    _ -> :ok
  end
  ```

  ### Parse DateTime (Opt-in)
  ```elixir
  # Fields are kept as strings - parse when needed
  sending_time_str = msg.fields |> List.keyfind("52", 0) |> elem(1)
  {:ok, datetime} = ExFixsense.Protocol.DateUtil.parse(sending_time_str)
  ```

  ### Validation
  ```elixir
  if msg.valid do
    process_message(msg)
  else
    Logger.error("Invalid message: \#{inspect(msg.error_reason)}")
  end
  ```

  ## Example

      # From ex_fix style handler
      def on_app_message(_session, msg_type, %InMessage{} = msg, _env) do
        if msg.valid and msg.complete do
          case msg_type do
            "8" ->
              # Execution report
              field_map = msg.fields |> Map.new()
              order_id = field_map["11"]
              status = field_map["39"]
              Logger.info("Order \#{order_id} status: \#{status}")

            _ ->
              Logger.debug("Received \#{msg_type}")
          end
        end
      end
  """

  @type t :: %__MODULE__{
          msg_type: String.t(),
          seqnum: integer(),
          fields: [{String.t(), String.t()}],
          original_fix_msg: binary(),
          valid: boolean(),
          complete: boolean(),
          poss_dup: boolean(),
          error_reason: term() | nil,
          subject: String.t() | nil,
          other_msgs: String.t(),
          rest_msg: String.t()
        }

  defstruct [
    :msg_type,
    :seqnum,
    :fields,
    :original_fix_msg,
    :valid,
    :complete,
    :poss_dup,
    :error_reason,
    :subject,
    :other_msgs,
    :rest_msg
  ]
end
