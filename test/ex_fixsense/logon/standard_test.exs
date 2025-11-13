defmodule ExFixsense.Logon.StandardTest do
  use ExUnit.Case, async: true
  alias ExFixsense.Logon.Standard

  describe "build_logon_fields/1" do
    test "returns standard FIX logon fields" do
      config = %{}
      fields = Standard.build_logon_fields(config)

      # EncryptMethod
      assert {"98", "0"} in fields
      # HeartBtInt
      assert {"108", "30"} in fields
      # ResetSeqNumFlag
      assert {"141", "Y"} in fields
    end

    test "returns exactly 3 fields" do
      config = %{}
      fields = Standard.build_logon_fields(config)

      assert length(fields) == 3
    end

    test "works with empty config" do
      fields = Standard.build_logon_fields(%{})

      assert is_list(fields)
      assert length(fields) == 3
    end

    test "ignores config content" do
      config = %{
        some_key: "some_value",
        logon_fields: %{username: "user"}
      }

      fields = Standard.build_logon_fields(config)

      assert length(fields) == 3
      assert {"98", "0"} in fields
    end
  end

end
