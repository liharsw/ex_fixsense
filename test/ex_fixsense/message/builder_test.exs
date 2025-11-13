defmodule ExFixsense.Message.BuilderTest do
  use ExUnit.Case, async: true
  alias ExFixsense.Message.{Builder, OutMessage}

  describe "new/1" do
    test "creates a new message with given type" do
      msg = Builder.new("D")

      assert %OutMessage{} = msg
      assert msg.msg_type == "D"
      assert msg.fields == []
    end

    test "creates messages for different types" do
      types = ["D", "V", "x", "AN", "H", "G"]

      for type <- types do
        msg = Builder.new(type)
        assert msg.msg_type == type
        assert msg.fields == []
      end
    end
  end

  describe "set_field/3" do
    test "sets a field value" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")

      assert Builder.get_field(msg, "55") == "BTC_USD"
    end

    test "sets multiple different fields" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("54", "1")
        |> Builder.set_field("38", "0.001")

      assert Builder.get_field(msg, "55") == "BTC_USD"
      assert Builder.get_field(msg, "54") == "1"
      assert Builder.get_field(msg, "38") == "0.001"
    end

    test "converts non-string values to strings" do
      msg =
        Builder.new("D")
        |> Builder.set_field("54", 1)
        |> Builder.set_field("38", 0.001)
        |> Builder.set_field("59", :atom_value)

      assert Builder.get_field(msg, "54") == "1"
      assert Builder.get_field(msg, "38") == "0.001"
      assert Builder.get_field(msg, "59") == "atom_value"
    end

    test "handles repeating groups (same tag multiple times)" do
      msg =
        Builder.new("V")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("55", "ETH_USD")
        |> Builder.set_field("55", "LTC_USD")

      assert Builder.get_field(msg, "55") == ["BTC_USD", "ETH_USD", "LTC_USD"]
    end

    test "overwrites single field when set again before repeating" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")

      # Setting again creates a list (repeating group)
      msg = Builder.set_field(msg, "55", "ETH_USD")

      assert Builder.get_field(msg, "55") == ["BTC_USD", "ETH_USD"]
    end

    test "chains correctly" do
      msg =
        Builder.new("D")
        |> Builder.set_field("11", "ORDER_123")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("54", "1")
        |> Builder.set_field("38", "0.1")
        |> Builder.set_field("40", "1")

      assert length(msg.fields) == 5
    end
  end

  describe "set_fields/2" do
    test "sets multiple fields from a map" do
      msg =
        Builder.new("D")
        |> Builder.set_fields(%{"55" => "BTC_USD", "54" => "1", "38" => "0.001"})

      assert Builder.get_field(msg, "55") == "BTC_USD"
      assert Builder.get_field(msg, "54") == "1"
      assert Builder.get_field(msg, "38") == "0.001"
    end

    test "sets multiple fields from a keyword list" do
      msg =
        Builder.new("D")
        |> Builder.set_fields([{"55", "BTC_USD"}, {"54", "1"}])

      assert Builder.get_field(msg, "55") == "BTC_USD"
      assert Builder.get_field(msg, "54") == "1"
    end

    test "converts keys to strings" do
      msg =
        Builder.new("D")
        |> Builder.set_fields(%{55 => "BTC_USD", 54 => 1})

      assert Builder.get_field(msg, "55") == "BTC_USD"
      assert Builder.get_field(msg, "54") == "1"
    end

    test "chains with other operations" do
      msg =
        Builder.new("D")
        |> Builder.set_field("11", "ORDER_123")
        |> Builder.set_fields(%{"55" => "BTC_USD", "54" => "1"})
        |> Builder.set_field("38", "0.1")

      assert length(msg.fields) == 4
    end
  end

  describe "get_field/2" do
    test "returns field value when set" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")

      assert Builder.get_field(msg, "55") == "BTC_USD"
    end

    test "returns nil when field not set" do
      msg = Builder.new("D")

      assert Builder.get_field(msg, "55") == nil
    end

    test "returns list for repeating groups" do
      msg =
        Builder.new("V")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("55", "ETH_USD")

      assert Builder.get_field(msg, "55") == ["BTC_USD", "ETH_USD"]
    end
  end

  describe "has_field?/2" do
    test "returns true when field is set" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")

      assert Builder.has_field?(msg, "55") == true
    end

    test "returns false when field is not set" do
      msg = Builder.new("D")

      assert Builder.has_field?(msg, "55") == false
    end

    test "returns true for repeating groups" do
      msg =
        Builder.new("V")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("55", "ETH_USD")

      assert Builder.has_field?(msg, "55") == true
    end
  end

  describe "remove_field/2" do
    test "removes a field" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("54", "1")
        |> Builder.remove_field("54")

      assert Builder.has_field?(msg, "55") == true
      assert Builder.has_field?(msg, "54") == false
    end

    test "does nothing if field doesn't exist" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.remove_field("99")

      assert Builder.has_field?(msg, "55") == true
      assert length(msg.fields) == 1
    end

    test "removes repeating groups" do
      msg =
        Builder.new("V")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("55", "ETH_USD")
        |> Builder.remove_field("55")

      assert Builder.has_field?(msg, "55") == false
    end

    test "chains correctly" do
      msg =
        Builder.new("D")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("54", "1")
        |> Builder.set_field("38", "0.1")
        |> Builder.remove_field("54")
        |> Builder.set_field("40", "1")

      assert Builder.has_field?(msg, "55") == true
      assert Builder.has_field?(msg, "54") == false
      assert Builder.has_field?(msg, "38") == true
      assert Builder.has_field?(msg, "40") == true
    end
  end

  describe "real-world message examples" do
    test "builds a market order" do
      msg =
        Builder.new("D")
        |> Builder.set_field("11", "ORD_#{System.system_time(:millisecond)}")
        |> Builder.set_field("55", "BTC_USD")
        |> Builder.set_field("54", "1")
        |> Builder.set_field("38", "0.1")
        |> Builder.set_field("40", "1")
        |> Builder.set_field("59", "4")

      assert msg.msg_type == "D"
      assert Builder.has_field?(msg, "11")
      assert Builder.get_field(msg, "55") == "BTC_USD"
      assert Builder.get_field(msg, "54") == "1"
      assert Builder.get_field(msg, "40") == "1"
    end

    test "builds a market data request" do
      msg =
        Builder.new("V")
        |> Builder.set_field("262", "MD_REQ_001")
        |> Builder.set_field("263", "1")
        |> Builder.set_field("264", "0")
        |> Builder.set_field("265", "0")
        |> Builder.set_field("267", "2")
        |> Builder.set_field("269", "0")
        |> Builder.set_field("269", "1")
        |> Builder.set_field("146", "1")
        |> Builder.set_field("55", "BTC_USD")

      assert msg.msg_type == "V"
      assert Builder.get_field(msg, "262") == "MD_REQ_001"
      assert Builder.get_field(msg, "269") == ["0", "1"]
      assert Builder.get_field(msg, "55") == "BTC_USD"
    end

    test "builds a security list request" do
      msg =
        Builder.new("x")
        |> Builder.set_field("320", "SEC_REQ_001")
        |> Builder.set_field("559", "4")
        |> Builder.set_field("263", "0")

      assert msg.msg_type == "x"
      assert Builder.get_field(msg, "320") == "SEC_REQ_001"
      assert Builder.get_field(msg, "559") == "4"
    end

    test "builds a position request" do
      msg =
        Builder.new("AN")
        |> Builder.set_field("710", "POS_REQ_001")
        |> Builder.set_field("724", "0")
        |> Builder.set_field("263", "1")

      assert msg.msg_type == "AN"
      assert Builder.get_field(msg, "710") == "POS_REQ_001"
      assert Builder.get_field(msg, "263") == "1"
    end
  end
end
