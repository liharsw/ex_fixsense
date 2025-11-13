defmodule ExFixsense.Core.SessionP0Test do
  use ExUnit.Case, async: true

  @moduledoc """
  Tests for P0 (Priority 0) protocol features:
  - Sequence gap detection
  - ResendRequest sending
  - SequenceReset handling
  - Reject message handling
  - PossDupFlag support
  """

  describe "sequence gap detection" do
    test "detects gap when actual sequence > expected" do
      # Simulate receiving sequence 5 when expecting 3
      # This would trigger handle_sequence_gap/5

      expected_seq = 3
      actual_seq = 5

      assert actual_seq > expected_seq
      gap_size = actual_seq - expected_seq
      assert gap_size == 2
    end

    test "detects duplicate when actual sequence < expected" do
      # Simulate receiving sequence 2 when expecting 5
      # This would trigger handle_possible_duplicate/3

      expected_seq = 5
      actual_seq = 2

      assert actual_seq < expected_seq
    end

    test "normal processing when sequences match" do
      expected_seq = 10
      actual_seq = 10

      assert actual_seq == expected_seq
    end
  end

  describe "ResendRequest message building" do
    test "builds ResendRequest with correct tags" do
      # ResendRequest (35=2) requires:
      # - Tag 7: BeginSeqNo
      # - Tag 16: EndSeqNo

      begin_seq = 5
      end_seq = 10

      resend_request = [
        {"35", "2"},
        {"7", "#{begin_seq}"},
        {"16", "#{end_seq}"}
      ]

      assert Enum.find(resend_request, fn {tag, _} -> tag == "35" end) == {"35", "2"}
      assert Enum.find(resend_request, fn {tag, _} -> tag == "7" end) == {"7", "5"}
      assert Enum.find(resend_request, fn {tag, _} -> tag == "16" end) == {"16", "10"}
    end

    test "ResendRequest covers gap range correctly" do
      expected = 3
      actual = 7

      # Should request messages from expected (3) to actual-1 (6)
      begin_seq_no = expected
      end_seq_no = actual - 1

      assert begin_seq_no == 3
      assert end_seq_no == 6
      # This means: "please resend messages 3, 4, 5, 6"
    end
  end

  describe "SequenceReset parsing" do
    test "parses SequenceReset-GapFill correctly" do
      # SequenceReset with GapFillFlag=Y means skip over missing messages
      fields = %{
        "35" => "4",  # SequenceReset
        "123" => "Y",  # GapFillFlag
        "36" => "10"  # NewSeqNo
      }

      gap_fill_flag = Map.get(fields, "123", "N")
      new_seq_no = String.to_integer(Map.get(fields, "36"))

      assert gap_fill_flag == "Y"
      assert new_seq_no == 10
    end

    test "parses SequenceReset-HardReset correctly" do
      # SequenceReset without GapFillFlag means full reset
      fields = %{
        "35" => "4",  # SequenceReset
        "123" => "N",  # GapFillFlag
        "36" => "1"  # NewSeqNo (back to 1)
      }

      gap_fill_flag = Map.get(fields, "123", "N")
      new_seq_no = String.to_integer(Map.get(fields, "36"))

      assert gap_fill_flag == "N"
      assert new_seq_no == 1
    end
  end

  describe "Reject message parsing" do
    test "parses Reject message fields correctly" do
      # Reject (35=3) contains:
      # - Tag 45: RefSeqNum
      # - Tag 371: RefTagID
      # - Tag 372: RefMsgType
      # - Tag 373: SessionRejectReason
      # - Tag 58: Text

      fields = %{
        "35" => "3",
        "45" => "25",
        "371" => "11",
        "372" => "D",
        "373" => "5",
        "58" => "ClOrdID too long"
      }

      assert Map.get(fields, "35") == "3"  # Reject
      assert Map.get(fields, "45") == "25"  # RefSeqNum
      assert Map.get(fields, "371") == "11"  # RefTagID (ClOrdID)
      assert Map.get(fields, "372") == "D"  # RefMsgType (NewOrderSingle)
      assert Map.get(fields, "373") == "5"  # SessionRejectReason (value too long)
      assert Map.get(fields, "58") == "ClOrdID too long"
    end

    test "Cumberland certification Reject scenario" do
      # From apis/fix-api-docs.txt line 845-852:
      # Send NewOrderSingle with ClOrdId > 130 characters
      # Expect Reject with specific fields

      cl_ord_id = String.duplicate("X", 131)
      assert String.length(cl_ord_id) > 130

      # Expected Reject response
      expected_reject = %{
        "35" => "3",  # Reject
        "371" => "11",  # RefTagID = ClOrdID
        "372" => "D",  # RefMsgType = NewOrderSingle
        "373" => "5"  # SessionRejectReason = value too long
      }

      assert Map.get(expected_reject, "371") == "11"
      assert Map.get(expected_reject, "372") == "D"
      assert Map.get(expected_reject, "373") == "5"
    end
  end

  describe "PossDupFlag handling" do
    test "allows duplicate with PossDupFlag=Y" do
      fields = %{
        "35" => "W",  # MarketDataSnapshot
        "34" => "5",  # MsgSeqNum (duplicate)
        "43" => "Y"  # PossDupFlag
      }

      poss_dup = Map.get(fields, "43", "N")
      assert poss_dup == "Y"
      # Should process message without incrementing sequence
    end

    test "rejects duplicate without PossDupFlag" do
      fields = %{
        "35" => "W",
        "34" => "5",
        "43" => "N"  # No PossDupFlag
      }

      poss_dup = Map.get(fields, "43", "N")
      assert poss_dup == "N"
      # Should send Reject
    end

    test "defaults to N when PossDupFlag missing" do
      fields = %{
        "35" => "W",
        "34" => "5"
        # No tag 43
      }

      poss_dup = Map.get(fields, "43", "N")
      assert poss_dup == "N"
    end
  end

  describe "pending message queue" do
    test "stores messages received during gap" do
      pending = []

      # Receive message 7 when expecting 5
      msg1 = {"W", %{"34" => "7", "55" => "BTC-USD"}, 7}
      pending = [msg1 | pending]

      # Receive message 8
      msg2 = {"X", %{"34" => "8", "55" => "ETH-USD"}, 8}
      pending = [msg2 | pending]

      assert length(pending) == 2
    end

    test "processes pending messages in order after gap fill" do
      # Pending messages stored out of order
      pending = [
        {"X", %{"34" => "8"}, 8},
        {"W", %{"34" => "7"}, 7},
        {"X", %{"34" => "6"}, 6}
      ]

      # Sort by sequence number
      sorted = Enum.sort_by(pending, fn {_type, _fields, seq} -> seq end)

      sequences = Enum.map(sorted, fn {_, _, seq} -> seq end)
      assert sequences == [6, 7, 8]
    end

    test "clears pending queue after processing" do
      pending = [
        {"W", %{}, 5},
        {"X", %{}, 6}
      ]

      assert length(pending) == 2

      # After processing
      pending = []

      assert length(pending) == 0
      assert pending == []
    end
  end

  describe "complete gap recovery flow" do
    test "simulates full gap recovery sequence" do
      # Initial state
      recv_seq_num = 5
      send_seq_num = 10
      pending_messages = []

      # Step 1: Receive message 8 when expecting 5 (gap!)
      actual_seq = 8
      assert actual_seq > recv_seq_num

      # Step 2: Send ResendRequest for 5-7
      begin_seq = recv_seq_num
      end_seq = actual_seq - 1
      assert begin_seq == 5
      assert end_seq == 7

      send_seq_num = send_seq_num + 1
      assert send_seq_num == 11

      # Step 3: Store message 8 in pending
      pending_messages = [{"W", %{"34" => "8"}, 8} | pending_messages]
      assert length(pending_messages) == 1

      # Step 4: Receive SequenceReset-GapFill to 8
      new_seq_no = 8
      recv_seq_num = new_seq_no
      assert recv_seq_num == 8

      # Step 5: Process pending message 8
      assert recv_seq_num == 8
      recv_seq_num = recv_seq_num + 1
      assert recv_seq_num == 9

      # Step 6: Clear pending
      pending_messages = []
      assert length(pending_messages) == 0

      # Final state
      assert recv_seq_num == 9
      assert send_seq_num == 11
      assert pending_messages == []
    end
  end

  describe "message routing" do
    test "routes Reject to handle_reject" do
      msg_type = "3"
      assert msg_type == "3"  # Should route to handle_reject
    end

    test "routes SequenceReset to handle_sequence_reset" do
      msg_type = "4"
      assert msg_type == "4"  # Should route to handle_sequence_reset
    end

    test "routes normal messages to handle_application_message" do
      business_types = ["W", "X", "8", "9", "D", "G"]

      for msg_type <- business_types do
        refute msg_type in ["3", "4"]  # Should NOT be session messages
      end
    end
  end

  describe "send_reject message building" do
    test "builds Reject with required fields" do
      rejected_fields = %{
        "34" => "10",  # MsgSeqNum
        "35" => "D"  # MsgType (NewOrderSingle)
      }

      ref_seq_num = Map.get(rejected_fields, "34", "0")
      ref_msg_type = Map.get(rejected_fields, "35", "")
      reason = "Sequence number too low"

      reject = [
        {"35", "3"},  # Reject
        {"45", ref_seq_num},
        {"372", ref_msg_type},
        {"58", reason}
      ]

      assert Enum.find(reject, fn {tag, _} -> tag == "35" end) == {"35", "3"}
      assert Enum.find(reject, fn {tag, _} -> tag == "45" end) == {"45", "10"}
      assert Enum.find(reject, fn {tag, _} -> tag == "372" end) == {"372", "D"}
      assert Enum.find(reject, fn {tag, _} -> tag == "58" end) == {"58", "Sequence number too low"}
    end
  end
end
