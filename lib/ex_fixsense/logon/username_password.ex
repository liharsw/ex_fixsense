defmodule ExFixsense.Logon.UsernamePassword do
  @moduledoc """
  Username/Password FIX logon strategy.

  Used by many brokers including Coinbase, Binance, FTX, and others
  that authenticate using Tag 553 (Username) and Tag 554 (Password).

  This strategy adds the username and password fields to the logon message.
  The credentials are typically API keys/secrets provided by the broker.

  ## FIX Tags

  - Tag 553 (Username): API key or username
  - Tag 554 (Password): API secret or password

  ## When to Use

  - Coinbase FIX API
  - Binance FIX API
  - Many retail and institutional brokers
  - Any broker using standard username/password authentication

  ## Configuration Example

      config :ex_fixsense, :sessions,
        coinbase: [
          host: "fix.coinbase.com",
          port: 4198,
          protocol_version: "FIX.4.2",
          transport: ExFixsense.Transport.TCP,

          # Use username/password logon
          logon_strategy: ExFixsense.Logon.UsernamePassword,

          # Credentials
          logon_fields: %{
            username: System.get_env("COINBASE_API_KEY"),
            password: System.get_env("COINBASE_API_SECRET")
          },

          sender_comp_id: "MY_FIRM",
          target_comp_id: "Coinbase"
        ]

  ## Usage

      # Start session with username/password auth
      {:ok, pid} = ExFixsense.start_session(
        "coinbase",
        :coinbase,
        MyCoinbaseHandler
      )

  ## Security Note

  Always use environment variables or secure vaults for credentials.
  Never hardcode API keys or secrets in your code or config files.

  ## Required Fields

  The `logon_fields` map must contain:
  - `:username` - The API key or username
  - `:password` - The API secret or password

  Missing either field will raise a `KeyError` when building the logon message.
  """

  @behaviour ExFixsense.Logon.Behaviour

  @impl true
  def build_logon_fields(config) do
    logon_fields = Map.get(config, :logon_fields, %{})

    # Extract username and password (will raise if missing)
    username = Map.fetch!(logon_fields, :username)
    password = Map.fetch!(logon_fields, :password)

    [
      # EncryptMethod (None)
      {"98", "0"},
      # HeartBtInt (30 seconds)
      {"108", "30"},
      # ResetSeqNumFlag
      {"141", "Y"},

      # Username/Password authentication
      # Username (API Key)
      {"553", username},
      # Password (API Secret)
      {"554", password}
    ]
  end

end
