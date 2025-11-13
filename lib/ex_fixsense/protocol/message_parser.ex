defmodule ExFixsense.Protocol.MessageParser do
  @moduledoc """
  Parses FIX 4.4 protocol messages.

  Handles:
  - Converting FIX messages to field maps
  - Converting FIX messages to InMessage structs
  - Splitting multiple messages in one TCP packet
  - Converting SOH delimiters to readable format

  ## How FIX Parsing Works

  FIX messages come as binary with SOH (\x01) delimiters:
  ```
  8=FIX.4.4\x0135=A\x0149=SENDER\x0156=TARGET\x01
  ```

  We can parse this into a map:
  ```elixir
  %{
    "8" => "FIX.4.4",
    "35" => "A",
    "49" => "SENDER",
    "56" => "TARGET"
  }
  ```

  Or into a rich InMessage struct:
  ```elixir
  %InMessage{
    msg_type: :logon,
    seq_num: 1,
    sender_comp_id: "SENDER",
    target_comp_id: "TARGET",
    raw: %{"8" => "FIX.4.4", ...}
  }
  ```

  ## Multiple Messages

  Sometimes Cumberland sends multiple messages in one TCP packet:
  ```
  8=FIX.4.4|35=AP|15=BTC|...8=FIX.4.4|35=AP|15=ETH|...8=FIX.4.4|35=AP|15=USD|...
  ```

  We split these into separate messages for individual parsing.
  """


  @doc """
  Parse a FIX message string into a map of fields.

  Expects message with "|" delimiters (SOH already converted to readable format).

  ## Parameters
  - message: String with fields separated by "|"

  ## Returns
  Map of %{tag => value}

  ## Example
      iex> parse("8=FIX.4.4|35=A|49=SENDER|56=TARGET|")
      %{"8" => "FIX.4.4", "35" => "A", "49" => "SENDER", "56" => "TARGET"}
  """
  def parse(message) do
    String.split(message, "|")
    |> Enum.map(fn field ->
      case String.split(field, "=", parts: 2) do
        [tag, value] -> {tag, value}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Map.new()
  end

  @doc """
  Split multiple FIX messages from single TCP packet.

  Cumberland sometimes sends multiple messages (e.g., Position Reports for BTC, ETH, USD)
  in one TCP packet. This function splits them into individual messages.

  ## Parameters
  - data: String containing one or more FIX messages

  ## Returns
  List of individual FIX message strings

  ## Example
      iex> data = "8=FIX.4.4|35=AP|15=BTC|...8=FIX.4.4|35=AP|15=ETH|..."
      iex> split(data)
      ["8=FIX.4.4|35=AP|15=BTC|...", "8=FIX.4.4|35=AP|15=ETH|..."]
  """
  def split(data) do
    # FIX messages are delimited by "8=FIX.4.4"
    data
    |> String.split(~r/(?=8=FIX\.4\.4)/, trim: true)
    |> Enum.filter(&(&1 != ""))
  end

  @doc """
  Convert SOH characters (\\x01) to readable pipes (|) for logging.

  FIX messages use SOH (Start of Header, ASCII 0x01) as field delimiter.
  This is hard to read in logs, so we convert to "|" for display.

  ## Parameters
  - binary_data: Binary FIX message with \\x01 delimiters

  ## Returns
  String with "|" delimiters
  """
  def to_readable(binary_data) do
    String.replace(binary_data, "\x01", "|")
  end
end
