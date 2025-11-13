defmodule ExFixsense.Message.Builder do
  @moduledoc """
  Fluent API for building FIX messages.

  This module provides a chainable interface for constructing FIX messages
  in a readable, declarative way.

  ## Basic Usage

      alias ExFixsense.Message.Builder

      # Build a new order
      msg = Builder.new("D")
            |> Builder.set_field("55", "BTC_USD")      # Symbol
            |> Builder.set_field("54", "1")            # Side (Buy)
            |> Builder.set_field("38", "0.001")        # OrderQty
            |> Builder.set_field("40", "1")            # OrdType (Market)

      # Send the message
      ExFixsense.send_message("my-session", msg)

  ## Message Types

  Common FIX message types:
  - `"D"` - New Order Single
  - `"V"` - Market Data Request
  - `"x"` - Security List Request
  - `"AN"` - Request for Positions
  - `"H"` - Order Status Request

  ## Field Tags

  Common FIX field tags:
  - `"11"` - ClOrdID (Client Order ID)
  - `"38"` - OrderQty (Order Quantity)
  - `"40"` - OrdType (Order Type: 1=Market, 2=Limit, D=Previously Quoted)
  - `"44"` - Price
  - `"54"` - Side (1=Buy, 2=Sell)
  - `"55"` - Symbol
  - `"59"` - TimeInForce (4=Fill Or Kill)
  - `"60"` - TransactTime

  ## Repeating Groups

  Some FIX messages require repeating groups (e.g., multiple symbols in market data request):

      msg = Builder.new("V")
            |> Builder.set_field("262", "MD_REQ_123")
            |> Builder.set_field("263", "1")
            |> Builder.set_field("146", "2")           # NoRelatedSym
            |> Builder.set_field("55", "BTC_USD")      # Symbol 1
            |> Builder.set_field("55", "ETH_USD")      # Symbol 2

  Note: For repeating groups, use `set_field` multiple times with the same tag.
  The builder will store them appropriately.

  ## Examples

  ### Market Order

      Builder.new("D")
      |> Builder.set_field("11", "ORD_#{System.system_time(:millisecond)}")
      |> Builder.set_field("55", "BTC_USD")
      |> Builder.set_field("54", "1")      # Buy
      |> Builder.set_field("38", "0.1")
      |> Builder.set_field("40", "1")      # Market
      |> Builder.set_field("59", "4")      # FOK

  ### Market Data Request

      Builder.new("V")
      |> Builder.set_field("262", "MD_REQ_001")
      |> Builder.set_field("263", "1")     # Subscribe
      |> Builder.set_field("264", "0")     # MarketDepth
      |> Builder.set_field("265", "0")     # MDUpdateType
      |> Builder.set_field("267", "2")     # NoMDEntryTypes
      |> Builder.set_field("269", "0")     # Bid
      |> Builder.set_field("269", "1")     # Offer
      |> Builder.set_field("146", "1")     # NoRelatedSym
      |> Builder.set_field("55", "BTC_USD")

  ### Security List Request

      Builder.new("x")
      |> Builder.set_field("320", "SEC_REQ_001")
      |> Builder.set_field("559", "4")     # All securities
      |> Builder.set_field("263", "0")     # Snapshot
  """

  alias ExFixsense.Message.OutMessage

  @doc """
  Create a new FIX message with the specified message type.

  ## Parameters

  - `msg_type` - FIX message type (Tag 35), e.g., "D" for New Order Single

  ## Returns

  An `OutMessage` struct ready to be populated with fields.

  ## Examples

      iex> Builder.new("D")
      %OutMessage{msg_type: "D", fields: []}

      iex> Builder.new("V")
      %OutMessage{msg_type: "V", fields: []}
  """
  @spec new(String.t()) :: OutMessage.t()
  def new(msg_type) when is_binary(msg_type) do
    %OutMessage{msg_type: msg_type, fields: []}
  end

  @doc """
  Set a field value in the message.

  If the field already exists, it will be overwritten.
  For repeating groups, the value will be appended to a list.

  ## Parameters

  - `message` - The `OutMessage` struct
  - `tag` - FIX field tag (e.g., "55" for Symbol)
  - `value` - Field value (will be converted to string)

  ## Returns

  Updated `OutMessage` struct.

  ## Examples

      iex> Builder.new("D")
      ...> |> Builder.set_field("55", "BTC_USD")
      ...> |> Builder.set_field("54", "1")
      %OutMessage{msg_type: "D", fields: [{"55", "BTC_USD"}, {"54", "1"}]}

      # Repeating the same tag (for repeating groups)
      iex> Builder.new("V")
      ...> |> Builder.set_field("55", "BTC_USD")
      ...> |> Builder.set_field("55", "ETH_USD")
      %OutMessage{msg_type: "V", fields: [{"55", ["BTC_USD", "ETH_USD"]}]}
  """
  @spec set_field(OutMessage.t(), String.t(), any()) :: OutMessage.t()
  def set_field(%OutMessage{} = message, tag, value) when is_binary(tag) do
    # Convert value to string
    str_value = to_string(value)

    # Check if field already exists (repeating group scenario)
    new_fields =
      case List.keyfind(message.fields, tag, 0) do
        nil ->
          # First occurrence - append to list (preserves insertion order)
          message.fields ++ [{tag, str_value}]

        {^tag, existing} when is_binary(existing) ->
          # Second occurrence - convert to list
          List.keyreplace(message.fields, tag, 0, {tag, [existing, str_value]})

        {^tag, existing} when is_list(existing) ->
          # Subsequent occurrences - append to existing list
          List.keyreplace(message.fields, tag, 0, {tag, existing ++ [str_value]})
      end

    %{message | fields: new_fields}
  end

  @doc """
  Set multiple fields at once from a map or keyword list.

  ## Parameters

  - `message` - The `OutMessage` struct
  - `fields` - Map or keyword list of {tag, value} pairs

  ## Returns

  Updated `OutMessage` struct.

  ## Examples

      iex> Builder.new("D")
      ...> |> Builder.set_fields(%{"55" => "BTC_USD", "54" => "1"})
      %OutMessage{msg_type: "D", fields: [{"55", "BTC_USD"}, {"54", "1"}]}

      iex> Builder.new("D")
      ...> |> Builder.set_fields([{"55", "BTC_USD"}, {"54", "1"}])
      %OutMessage{msg_type: "D", fields: [{"55", "BTC_USD"}, {"54", "1"}]}
  """
  @spec set_fields(OutMessage.t(), map() | keyword()) :: OutMessage.t()
  def set_fields(%OutMessage{} = message, fields) when is_map(fields) do
    Enum.reduce(fields, message, fn {tag, value}, acc ->
      set_field(acc, to_string(tag), value)
    end)
  end

  def set_fields(%OutMessage{} = message, fields) when is_list(fields) do
    Enum.reduce(fields, message, fn {tag, value}, acc ->
      set_field(acc, to_string(tag), value)
    end)
  end

  @doc """
  Get the current value of a field.

  ## Parameters

  - `message` - The `OutMessage` struct
  - `tag` - FIX field tag

  ## Returns

  The field value, or `nil` if not set.

  ## Examples

      iex> msg = Builder.new("D") |> Builder.set_field("55", "BTC_USD")
      iex> Builder.get_field(msg, "55")
      "BTC_USD"

      iex> msg = Builder.new("D")
      iex> Builder.get_field(msg, "55")
      nil
  """
  @spec get_field(OutMessage.t(), String.t()) :: String.t() | [String.t()] | nil
  def get_field(%OutMessage{} = message, tag) when is_binary(tag) do
    case List.keyfind(message.fields, tag, 0) do
      {^tag, value} -> value
      nil -> nil
    end
  end

  @doc """
  Check if a field is set in the message.

  ## Parameters

  - `message` - The `OutMessage` struct
  - `tag` - FIX field tag

  ## Returns

  `true` if the field exists, `false` otherwise.

  ## Examples

      iex> msg = Builder.new("D") |> Builder.set_field("55", "BTC_USD")
      iex> Builder.has_field?(msg, "55")
      true

      iex> Builder.has_field?(msg, "54")
      false
  """
  @spec has_field?(OutMessage.t(), String.t()) :: boolean()
  def has_field?(%OutMessage{} = message, tag) when is_binary(tag) do
    List.keymember?(message.fields, tag, 0)
  end

  @doc """
  Remove a field from the message.

  ## Parameters

  - `message` - The `OutMessage` struct
  - `tag` - FIX field tag to remove

  ## Returns

  Updated `OutMessage` struct.

  ## Examples

      iex> msg = Builder.new("D")
      ...> |> Builder.set_field("55", "BTC_USD")
      ...> |> Builder.set_field("54", "1")
      iex> Builder.remove_field(msg, "54")
      %OutMessage{msg_type: "D", fields: [{"55", "BTC_USD"}]}
  """
  @spec remove_field(OutMessage.t(), String.t()) :: OutMessage.t()
  def remove_field(%OutMessage{} = message, tag) when is_binary(tag) do
    %{message | fields: List.keydelete(message.fields, tag, 0)}
  end
end
