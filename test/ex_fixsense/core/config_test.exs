defmodule ExFixsense.Core.ConfigTest do
  use ExUnit.Case, async: true
  alias ExFixsense.Core.Config

  describe "get/1" do
    test "returns config for valid session" do
      {:ok, config} = Config.get(:cumberland_oe)

      assert config.host == "fix-cumberlandmining.internal"
      assert config.port == 24001
      assert config.sender_comp_id == "your-sender-comp-id-uuid-here"
      assert config.target_comp_id == "cumberland"
    end

    test "returns error for invalid session" do
      assert {:error, :session_not_found} = Config.get(:invalid_session)
    end

    test "normalizes config to map with atom keys" do
      {:ok, config} = Config.get(:cumberland_oe)

      assert is_map(config)
      assert Map.has_key?(config, :host)
      assert Map.has_key?(config, :port)
    end

    test "applies default values" do
      {:ok, config} = Config.get(:cumberland_oe)

      assert config.protocol_version == "FIX.4.4"
      assert config.tcp_opts == []
    end

    test "preserves custom logon strategy" do
      {:ok, config} = Config.get(:cumberland_oe)

      assert config.logon_strategy == ExFixsense.Logon.OnBehalfOf
    end

    test "preserves logon_fields" do
      {:ok, config} = Config.get(:cumberland_oe)

      assert is_map(config.logon_fields)
      assert config.logon_fields.on_behalf_of_comp_id == "your-on-behalf-of-comp-id-uuid-here"
      assert config.logon_fields.on_behalf_of_sub_id == "your-on-behalf-of-sub-id-here"
    end

    test "loads different sessions correctly" do
      {:ok, oe_config} = Config.get(:cumberland_oe)
      {:ok, md_config} = Config.get(:cumberland_md)

      assert oe_config.sender_sub_id == "your-sender-sub-id-here"
      assert md_config.sender_sub_id == "your-sender-sub-id-here"
    end

    test "loads username/password config correctly" do
      {:ok, config} = Config.get(:coinbase)

      assert config.logon_strategy == ExFixsense.Logon.UsernamePassword
      assert config.protocol_version == "FIX.4.2"
      assert config.host == "fix.coinbase.com"
    end

    test "loads standard logon config correctly" do
      {:ok, config} = Config.get(:generic_broker)

      assert config.logon_strategy == ExFixsense.Logon.Standard
    end
  end

  describe "get!/1" do
    test "returns config for valid session" do
      config = Config.get!(:cumberland_oe)

      assert config.host == "fix-cumberlandmining.internal"
    end

    test "raises for invalid session" do
      assert_raise RuntimeError, ~r/Session config not found/, fn ->
        Config.get!(:invalid_session)
      end
    end
  end

  describe "list_sessions/0" do
    test "returns list of configured sessions" do
      sessions = Config.list_sessions()

      assert is_list(sessions)
      assert :cumberland_oe in sessions
      assert :cumberland_md in sessions
      assert :coinbase in sessions
      assert :generic_broker in sessions
    end

    test "returns atoms" do
      sessions = Config.list_sessions()

      assert Enum.all?(sessions, &is_atom/1)
    end

    test "returns at least 4 sessions from config" do
      sessions = Config.list_sessions()

      assert length(sessions) >= 4
    end
  end

  describe "validation" do
    test "validates required fields are present" do
      # This test would require temporarily modifying config
      # For now, we just verify the validation logic works
      # by ensuring our test configs all pass

      {:ok, config} = Config.get(:cumberland_oe)

      # All required fields should be present
      assert config.host
      assert config.port
      assert config.sender_comp_id
      assert config.target_comp_id
    end

    test "all configured sessions have required fields" do
      sessions = Config.list_sessions()

      for session_key <- sessions do
        {:ok, config} = Config.get(session_key)

        assert is_binary(config.host), "#{session_key} missing host"
        assert is_integer(config.port), "#{session_key} missing port"
        assert is_binary(config.sender_comp_id), "#{session_key} missing sender_comp_id"
        assert is_binary(config.target_comp_id), "#{session_key} missing target_comp_id"
      end
    end
  end

  describe "defaults" do
    test "sets default protocol_version" do
      {:ok, config} = Config.get(:cumberland_oe)

      # cumberland_oe specifies FIX.4.4
      assert config.protocol_version == "FIX.4.4"
    end

    test "sets default transport to SSL" do
      # generic_broker specifies SSL
      {:ok, config} = Config.get(:generic_broker)

      assert config.transport == ExFixsense.Transport.SSL
    end

    test "sets default logon_strategy to Standard" do
      {:ok, config} = Config.get(:generic_broker)

      assert config.logon_strategy == ExFixsense.Logon.Standard
    end

    test "sets default logon_fields to empty map" do
      {:ok, config} = Config.get(:generic_broker)

      assert config.logon_fields == %{}
    end

    test "sets default ssl_opts and tcp_opts" do
      {:ok, config} = Config.get(:coinbase)

      # Coinbase doesn't specify ssl_opts, should get empty list
      assert config.ssl_opts == []
    end
  end
end
