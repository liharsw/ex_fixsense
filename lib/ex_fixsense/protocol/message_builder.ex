defmodule ExFixsense.Protocol.MessageBuilder do
  @moduledoc """
  Builds FIX 4.4 protocol messages.

  Handles:
  - Message formatting with SOH delimiters (\x01)
  - Body length calculation
  - Checksum calculation

  ## How FIX Messages Work

  A FIX message has this structure:
  ```
  8=FIX.4.4|9=123|35=A|...|10=045|
  ```

  Where:
  - 8  = BeginString (always "FIX.4.4")
  - 9  = BodyLength (byte count of everything after tag 9)
  - 35 = MsgType (A=Logon, D=NewOrder, etc.)
  - 10 = CheckSum (sum of all bytes mod 256)
  - | represents SOH character (\x01)

  ## Example

      iex> fields = [
      ...>   {"8", "FIX.4.4"},
      ...>   {"35", "A"},
      ...>   {"49", "SENDER"},
      ...>   {"56", "TARGET"}
      ...> ]
      iex> ExFixsense.Protocol.MessageBuilder.build(fields)
      # Returns binary FIX message with checksum
  """

  @doc """
  Build a complete FIX message from field list.

  Expects fields list with BeginString as first element.
  Automatically calculates BodyLength (tag 9) and CheckSum (tag 10).

  ## Parameters
  - fields: List of {tag, value} tuples, starting with {"8", "FIX.4.4"}

  ## Returns
  Binary FIX message ready to send over socket
  """
  def build(fields) do
    # Build message body (everything except BeginString, BodyLength, and CheckSum)
    # Skip BeginString
    body_fields = Enum.drop(fields, 1)
    body = Enum.map_join(body_fields, "", fn {tag, value} -> "#{tag}=#{value}\x01" end)

    # Calculate body length
    body_length = byte_size(body)

    # Build complete message with BodyLength
    message_with_length = "8=FIX.4.4\x01" <> "9=#{body_length}\x01" <> body

    # Calculate checksum
    checksum = calculate_checksum(message_with_length)

    # Complete message with checksum
    message_with_length <> "10=#{checksum}\x01"
  end

  @doc """
  Calculate FIX checksum.

  Checksum = (sum of all bytes in message) mod 256
  Result is zero-padded to 3 digits.

  ## Example
      iex> calculate_checksum("8=FIX.4.4\\x0135=A\\x01")
      # Returns "045" or similar
  """
  def calculate_checksum(message) do
    checksum =
      :binary.bin_to_list(message)
      |> Enum.sum()
      |> rem(256)

    String.pad_leading("#{checksum}", 3, "0")
  end
end
