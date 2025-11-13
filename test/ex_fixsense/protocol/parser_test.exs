defmodule ExFixsense.Protocol.ParserTest do
  use ExUnit.Case, async: true

  alias ExFixsense.Protocol.Parser
  alias ExFixsense.Message.InMessage

  describe "validate_and_parse/1" do
    test "parses valid FIX message" do
      message = "8=FIX.4.4|9=100|35=D|34=42|49=SENDER|56=TARGET|52=20250104-14:30:45|55=BTC-USD|10=123|"

      assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)
      assert msg.msg_type == "D"
      assert msg.seqnum == 42
      assert msg.valid == true
      assert msg.complete == true
      assert msg.poss_dup == false
      assert msg.original_fix_msg == message
      assert is_list(msg.fields)
      assert length(msg.fields) > 0
    end

    test "extracts all fields as tuples" do
      message = "8=FIX.4.4|35=8|34=99|55=ETH-USD|39=2|10=456|"

      assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)
      assert {"8", "FIX.4.4"} in msg.fields
      assert {"35", "8"} in msg.fields
      assert {"34", "99"} in msg.fields
      assert {"55", "ETH-USD"} in msg.fields
      assert {"39", "2"} in msg.fields
    end

    test "detects PossDupFlag when present" do
      message = "8=FIX.4.4|35=D|34=42|43=Y|10=123|"

      assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)
      assert msg.poss_dup == true
    end

    test "poss_dup is false when flag not present" do
      message = "8=FIX.4.4|35=D|34=42|10=123|"

      assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)
      assert msg.poss_dup == false
    end

    test "returns error when MsgType missing" do
      message = "8=FIX.4.4|34=42|10=123|"

      assert {:error, :missing_required_field} = Parser.validate_and_parse(message)
    end

    test "returns error when MsgSeqNum missing" do
      message = "8=FIX.4.4|35=D|10=123|"

      assert {:error, :missing_required_field} = Parser.validate_and_parse(message)
    end

    test "returns error when MsgSeqNum invalid" do
      message = "8=FIX.4.4|35=D|34=invalid|10=123|"

      assert {:error, :invalid_seq_num} = Parser.validate_and_parse(message)
    end

    test "parses different message types" do
      messages = [
        {"8=FIX.4.4|35=A|34=1|10=123|", "A"},
        {"8=FIX.4.4|35=0|34=2|10=234|", "0"},
        {"8=FIX.4.4|35=D|34=3|10=345|", "D"},
        {"8=FIX.4.4|35=8|34=4|10=456|", "8"},
        {"8=FIX.4.4|35=W|34=5|10=567|", "W"}
      ]

      for {message, expected_type} <- messages do
        assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)
        assert msg.msg_type == expected_type
      end
    end
  end

  describe "fields_to_map/1" do
    test "converts fields list to map" do
      msg = %InMessage{
        msg_type: "8",
        seqnum: 42,
        fields: [{"35", "8"}, {"55", "BTC-USD"}, {"39", "2"}],
        original_fix_msg: "",
        valid: true,
        complete: true,
        poss_dup: false,
        error_reason: nil,
        subject: nil,
        other_msgs: "",
        rest_msg: ""
      }

      field_map = Parser.fields_to_map(msg)

      assert field_map["35"] == "8"
      assert field_map["55"] == "BTC-USD"
      assert field_map["39"] == "2"
    end

    test "handles empty fields list" do
      msg = %InMessage{
        msg_type: "D",
        seqnum: 1,
        fields: [],
        original_fix_msg: "",
        valid: true,
        complete: true,
        poss_dup: false,
        error_reason: nil,
        subject: nil,
        other_msgs: "",
        rest_msg: ""
      }

      field_map = Parser.fields_to_map(msg)
      assert field_map == %{}
    end
  end

  describe "workflow" do
    test "two-phase parsing workflow" do
      message = "8=FIX.4.4|35=8|34=99|49=BROKER|56=CLIENT|55=ETH-USD|11=ORDER-789|39=2|10=456|"

      # Phase 1: Validate and parse
      assert {:ok, %InMessage{} = msg} = Parser.validate_and_parse(message)

      # Check validation
      assert msg.valid == true

      # Route by msg_type
      case msg.msg_type do
        "8" ->
          # Phase 2: Convert to map when needed
          fields = Parser.fields_to_map(msg)
          assert fields["11"] == "ORDER-789"
          assert fields["55"] == "ETH-USD"
          assert fields["39"] == "2"
      end
    end
  end
end
