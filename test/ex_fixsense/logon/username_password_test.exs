defmodule ExFixsense.Logon.UsernamePasswordTest do
  use ExUnit.Case, async: true
  alias ExFixsense.Logon.UsernamePassword

  describe "build_logon_fields/1" do
    test "returns logon fields with username and password" do
      config = %{
        logon_fields: %{
          username: "test_api_key",
          password: "test_secret"
        }
      }

      fields = UsernamePassword.build_logon_fields(config)

      # EncryptMethod
      assert {"98", "0"} in fields
      # HeartBtInt
      assert {"108", "30"} in fields
      # ResetSeqNumFlag
      assert {"141", "Y"} in fields
      # Username
      assert {"553", "test_api_key"} in fields
      # Password
      assert {"554", "test_secret"} in fields
    end

    test "returns exactly 5 fields" do
      config = %{
        logon_fields: %{
          username: "user",
          password: "pass"
        }
      }

      fields = UsernamePassword.build_logon_fields(config)

      assert length(fields) == 5
    end

    test "raises KeyError when username missing" do
      config = %{
        logon_fields: %{
          password: "test_pass"
        }
      }

      assert_raise KeyError, fn ->
        UsernamePassword.build_logon_fields(config)
      end
    end

    test "raises KeyError when password missing" do
      config = %{
        logon_fields: %{
          username: "test_user"
        }
      }

      assert_raise KeyError, fn ->
        UsernamePassword.build_logon_fields(config)
      end
    end

    test "raises KeyError when logon_fields missing" do
      config = %{}

      assert_raise KeyError, fn ->
        UsernamePassword.build_logon_fields(config)
      end
    end

    test "handles environment variable values" do
      config = %{
        logon_fields: %{
          username: System.get_env("USER", "default_user"),
          password: "secret_from_env"
        }
      }

      fields = UsernamePassword.build_logon_fields(config)

      assert {"553", _username} = List.keyfind(fields, "553", 0)
      assert {"554", "secret_from_env"} in fields
    end
  end

end
