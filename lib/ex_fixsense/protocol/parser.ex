defmodule ExFixsense.Protocol.Parser do
  @moduledoc """
  FIX message parser with two-phase approach.

  ## Two-Phase Parsing

  **Phase 1: `validate_and_parse/1`** - Fast validation + create InMessage
  - Validates message format
  - Extracts critical fields (msg_type, seqnum, poss_dup)
  - Parses all fields to list of tuples
  - Returns InMessage struct with validation metadata

  **Phase 2: `fields_to_map/1`** - Convert to map (opt-in)
  - User calls this when they need map access
  - Converts fields list to map for easy access
  - Opt-in for performance (not called automatically)

  ## Usage

      # Phase 1: Validate and parse (always)
      {:ok, msg} = Parser.validate_and_parse(raw_fix_message)

      # Check validation
      if msg.valid do
        # Route by message type
        case msg.msg_type do
          "8" ->
            # Phase 2: Convert to map when needed (opt-in)
            fields = Parser.fields_to_map(msg)
            order_id = fields["11"]
            status = fields["39"]

          "W" ->
            # Or access fields directly from list
            symbol = List.keyfind(msg.fields, "55", 0) |> elem(1)

          _ ->
            :ok
        end
      end

  ## Performance

  Phase 1 is optimized for:
  - Fast validation (can reject invalid messages immediately)
  - Minimal processing (only what's needed for routing)
  - No unnecessary map creation

  Phase 2 only runs when user needs it (opt-in).
  """

  alias ExFixsense.Message.InMessage

  @doc """
  Validate FIX message and parse into InMessage struct.

  Performs validation and extracts:
  - Message type (tag 35)
  - Sequence number (tag 34)
  - All fields as list of tuples
  - PossDupFlag (tag 43)
  - Original binary message

  Returns InMessage with validation metadata.

  ## Parameters

  - `message_str` - FIX message string with "|" delimiters

  ## Returns

  - `{:ok, %InMessage{}}` - Successfully parsed and validated
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> Parser.validate_and_parse("8=FIX.4.4|35=D|34=42|55=BTC-USD|10=123|")
      {:ok, %InMessage{
        msg_type: "D",
        seqnum: 42,
        fields: [{"8", "FIX.4.4"}, {"35", "D"}, {"34", "42"}, ...],
        valid: true,
        complete: true
      }}

      iex> Parser.validate_and_parse("invalid")
      {:error, :invalid_format}
  """
  def validate_and_parse(message_str) when is_binary(message_str) do
    # Split into field strings
    fields_list = String.split(message_str, "|", trim: true)

    # Parse each field into {tag, value} tuples
    fields =
      Enum.map(fields_list, fn field ->
        case String.split(field, "=", parts: 2) do
          [tag, value] -> {tag, value}
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

    # Extract and validate critical fields
    case extract_critical(fields) do
      {:ok, msg_type, seqnum, poss_dup} ->
        {:ok,
         %InMessage{
           msg_type: msg_type,
           seqnum: seqnum,
           fields: fields,
           original_fix_msg: message_str,
           valid: true,
           complete: true,
           poss_dup: poss_dup,
           error_reason: nil,
           subject: nil,
           other_msgs: "",
           rest_msg: ""
         }}

      {:error, reason} ->
        # Return InMessage with validation error
        {:error, reason}
    end
  rescue
    e ->
      {:error, {:parse_exception, e}}
  end

  @doc """
  Convert InMessage fields to map.

  User calls this when they need map access to fields.
  This is opt-in for performance (not called automatically).

  ## Parameters

  - `msg` - InMessage struct with fields list

  ## Returns

  Map of field tag => value

  ## Examples

      iex> msg = %InMessage{fields: [{"35", "8"}, {"55", "BTC-USD"}, {"39", "2"}]}
      iex> Parser.fields_to_map(msg)
      %{"35" => "8", "55" => "BTC-USD", "39" => "2"}

  ## Usage Pattern

      def on_app_message(_session, "8", %InMessage{} = msg, _env) do
        # Convert to map when you need easy access
        fields = Parser.fields_to_map(msg)

        order_id = fields["11"]
        symbol = fields["55"]
        status = fields["39"]

        process_execution_report(order_id, symbol, status)
      end
  """
  def fields_to_map(%InMessage{fields: fields}) do
    Map.new(fields)
  end

  # Extract critical fields: msg_type (35), seqnum (34), poss_dup (43)
  defp extract_critical(fields) do
    with {_, msg_type} <- List.keyfind(fields, "35", 0),
         {_, seq_str} <- List.keyfind(fields, "34", 0),
         {seq_num, ""} <- Integer.parse(seq_str) do
      # Check for PossDupFlag (optional field)
      poss_dup =
        case List.keyfind(fields, "43", 0) do
          {_, "Y"} -> true
          _ -> false
        end

      {:ok, msg_type, seq_num, poss_dup}
    else
      nil -> {:error, :missing_required_field}
      :error -> {:error, :invalid_seq_num}
      _ -> {:error, :invalid_format}
    end
  end
end
