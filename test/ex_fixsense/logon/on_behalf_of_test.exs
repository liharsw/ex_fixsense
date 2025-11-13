defmodule ExFixsense.Logon.OnBehalfOfTest do
  use ExUnit.Case, async: true
  alias ExFixsense.Logon.OnBehalfOf

  describe "build_logon_fields/1" do
    test "returns logon fields WITHOUT OnBehalfOf tags" do
      config = %{
        logon_fields: %{
          on_behalf_of_comp_id: "a9def498-5bf7-422f-975b-9c67f444930c",
          on_behalf_of_sub_id: "tennet_cce"
        }
      }

      fields = OnBehalfOf.build_logon_fields(config)

      # Should contain standard fields
      assert {"98", "0"} in fields
      assert {"108", "30"} in fields
      assert {"141", "Y"} in fields

      # Should NOT contain OnBehalfOf tags (per Cumberland docs line 86)
      refute Enum.any?(fields, fn {tag, _} -> tag == "115" end)
      refute Enum.any?(fields, fn {tag, _} -> tag == "116" end)
    end

    test "returns exactly 3 fields (standard only)" do
      config = %{
        logon_fields: %{
          on_behalf_of_comp_id: "comp_id",
          on_behalf_of_sub_id: "sub_id"
        }
      }

      fields = OnBehalfOf.build_logon_fields(config)

      assert length(fields) == 3
    end

    test "ignores logon_fields content for logon message" do
      config = %{logon_fields: %{}}
      fields = OnBehalfOf.build_logon_fields(config)

      assert length(fields) == 3
      assert {"98", "0"} in fields
    end

    test "works with empty config" do
      fields = OnBehalfOf.build_logon_fields(%{})

      assert is_list(fields)
      assert length(fields) == 3
    end
  end

  describe "compliance with Cumberland API docs" do
    test "logon message does not require OnBehalfOf (line 86)" do
      # Per Cumberland docs line 86:
      # "not required on Administrative messages such as Logon, Logout, Heartbeat"

      config = %{
        logon_fields: %{
          on_behalf_of_comp_id: "a9def498-5bf7-422f-975b-9c67f444930c",
          on_behalf_of_sub_id: "tennet_cce"
        }
      }

      logon_fields = OnBehalfOf.build_logon_fields(config)

      # Verify NO OnBehalfOf in administrative (logon) message
      refute Enum.any?(logon_fields, fn {tag, _} -> tag in ["115", "116"] end)
    end
  end
end
