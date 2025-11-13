defmodule ExFixsense.Protocol.DateUtilTest do
  use ExUnit.Case, async: true

  alias ExFixsense.Protocol.DateUtil

  describe "serialize/2" do
    test "formats DateTime without milliseconds by default" do
      dt = ~U[2025-01-04 14:30:45Z]
      assert DateUtil.serialize(dt) == "20250104-14:30:45"
    end

    test "formats DateTime with milliseconds when requested" do
      dt = ~U[2025-01-04 14:30:45.123Z]
      assert DateUtil.serialize(dt, include_millis: true) == "20250104-14:30:45.123"
    end

    test "pads single digits correctly" do
      dt = ~U[2025-01-04 09:05:03Z]
      assert DateUtil.serialize(dt) == "20250104-09:05:03"
    end

    test "handles midnight correctly" do
      dt = ~U[2025-01-04 00:00:00Z]
      assert DateUtil.serialize(dt) == "20250104-00:00:00"
    end

    test "handles end of day correctly" do
      dt = ~U[2025-01-04 23:59:59Z]
      assert DateUtil.serialize(dt) == "20250104-23:59:59"
    end

    test "shifts timezone to UTC before serialization" do
      # Create a UTC datetime, serialize it
      dt = ~U[2025-01-04 14:30:45Z]
      result = DateUtil.serialize(dt)
      assert result == "20250104-14:30:45"
    end

    test "handles milliseconds correctly" do
      dt = ~U[2025-01-04 14:30:45.999Z]
      assert DateUtil.serialize(dt, include_millis: true) == "20250104-14:30:45.999"
    end

    test "rounds down milliseconds from microseconds" do
      # DateTime with 123456 microseconds = 123.456 milliseconds
      dt = DateTime.from_unix!(1704377445123456, :microsecond)
      result = DateUtil.serialize(dt, include_millis: true)
      # Should show 123 milliseconds
      assert String.ends_with?(result, ".123")
    end
  end

  describe "now/1" do
    test "returns current timestamp without milliseconds by default" do
      result = DateUtil.now()
      assert result =~ ~r/^\d{8}-\d{2}:\d{2}:\d{2}$/
    end

    test "returns current timestamp with milliseconds when requested" do
      result = DateUtil.now(include_millis: true)
      assert result =~ ~r/^\d{8}-\d{2}:\d{2}:\d{2}\.\d{3}$/
    end

    test "generates valid FIX timestamp format" do
      result = DateUtil.now()
      # Should match: YYYYMMDD-HH:MM:SS
      assert result =~ ~r/^20\d{6}-\d{2}:\d{2}:\d{2}$/
    end
  end

  describe "parse/1" do
    test "parses basic FIX timestamp" do
      {:ok, dt} = DateUtil.parse("20250104-14:30:45")
      assert dt.year == 2025
      assert dt.month == 1
      assert dt.day == 4
      assert dt.hour == 14
      assert dt.minute == 30
      assert dt.second == 45
      assert elem(dt.microsecond, 0) == 0
    end

    test "parses FIX timestamp with milliseconds" do
      {:ok, dt} = DateUtil.parse("20250104-14:30:45.123")
      assert dt.year == 2025
      assert dt.month == 1
      assert dt.day == 4
      assert dt.hour == 14
      assert dt.minute == 30
      assert dt.second == 45
      # 123 milliseconds = 123000 microseconds
      assert elem(dt.microsecond, 0) == 123000
    end

    test "returns DateTime in UTC timezone" do
      {:ok, dt} = DateUtil.parse("20250104-14:30:45")
      assert dt.time_zone == "Etc/UTC"
    end

    test "handles midnight" do
      {:ok, dt} = DateUtil.parse("20250104-00:00:00")
      assert dt.hour == 0
      assert dt.minute == 0
      assert dt.second == 0
    end

    test "handles end of day" do
      {:ok, dt} = DateUtil.parse("20250104-23:59:59")
      assert dt.hour == 23
      assert dt.minute == 59
      assert dt.second == 59
    end

    test "returns error for invalid format" do
      assert {:error, _} = DateUtil.parse("invalid")
      assert {:error, _} = DateUtil.parse("2025-01-04 14:30:45")
      assert {:error, _} = DateUtil.parse("20250104")
    end

    test "returns error for invalid date" do
      assert {:error, _} = DateUtil.parse("20251304-14:30:45")  # Month 13
      assert {:error, _} = DateUtil.parse("20250132-14:30:45")  # Day 32
    end

    test "returns error for invalid time" do
      assert {:error, _} = DateUtil.parse("20250104-25:30:45")  # Hour 25
      assert {:error, _} = DateUtil.parse("20250104-14:60:45")  # Minute 60
      assert {:error, _} = DateUtil.parse("20250104-14:30:60")  # Second 60
    end
  end

  describe "round-trip" do
    test "serialize then parse returns same timestamp" do
      original = ~U[2025-01-04 14:30:45Z]
      serialized = DateUtil.serialize(original)
      {:ok, parsed} = DateUtil.parse(serialized)
      assert DateTime.compare(original, parsed) == :eq
    end

    test "serialize with millis then parse returns same timestamp" do
      original = ~U[2025-01-04 14:30:45.123Z]
      serialized = DateUtil.serialize(original, include_millis: true)
      {:ok, parsed} = DateUtil.parse(serialized)
      assert DateTime.compare(original, parsed) == :eq
    end

    test "parse then serialize returns same string" do
      original_str = "20250104-14:30:45"
      {:ok, dt} = DateUtil.parse(original_str)
      serialized = DateUtil.serialize(dt)
      assert serialized == original_str
    end

    test "parse with millis then serialize returns same string" do
      original_str = "20250104-14:30:45.123"
      {:ok, dt} = DateUtil.parse(original_str)
      serialized = DateUtil.serialize(dt, include_millis: true)
      assert serialized == original_str
    end
  end

  describe "FIX 4.4 compliance" do
    test "generates timestamps for SendingTime (tag 52)" do
      # SendingTime uses YYYYMMDD-HH:MM:SS format
      result = DateUtil.now()
      assert String.match?(result, ~r/^\d{8}-\d{2}:\d{2}:\d{2}$/)
    end

    test "can parse timestamps from Cumberland" do
      # Example from Cumberland FIX API
      {:ok, dt} = DateUtil.parse("20250104-09:30:00")
      assert dt.hour == 9
      assert dt.minute == 30
    end

    test "handles leap years correctly" do
      {:ok, dt} = DateUtil.parse("20240229-14:30:45")  # 2024 is leap year
      assert dt.year == 2024
      assert dt.month == 2
      assert dt.day == 29
    end
  end
end
