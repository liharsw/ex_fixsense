defmodule ExFixsense.Logon.Standard do
  @moduledoc """
  Standard/minimal FIX logon strategy.

  Use this for brokers that don't require special authentication fields
  beyond the basic FIX logon requirements.

  This strategy only includes the minimal required logon fields:
  - Tag 98 (EncryptMethod): Set to "0" (None)
  - Tag 108 (HeartBtInt): Set to "30" seconds
  - Tag 141 (ResetSeqNumFlag): Set to "Y"

  ## When to Use

  - Brokers that authenticate via SSL client certificates only
  - Brokers with no additional authentication fields
  - Testing/development environments
  - Generic FIX connections

  ## Configuration Example

      config :ex_fixsense, :sessions,
        my_broker: [
          host: "fix.broker.com",
          port: 9876,
          protocol_version: "FIX.4.4",
          transport: ExFixsense.Transport.SSL,

          # Use standard logon (no special auth)
          logon_strategy: ExFixsense.Logon.Standard,

          sender_comp_id: "MY_FIRM",
          target_comp_id: "BROKER",

          ssl_opts: [
            certfile: "certs/client.crt",
            keyfile: "certs/client.key"
          ]
        ]

  ## Usage

      # Start session with standard logon
      {:ok, pid} = ExFixsense.start_session(
        "my-session",
        :my_broker,
        MyHandler
      )

  The session will logon with only the basic required fields.
  Authentication is handled by the SSL certificate.
  """

  @behaviour ExFixsense.Logon.Behaviour

  @impl true
  def build_logon_fields(_config) do
    [
      # EncryptMethod (None - typically using SSL)
      {"98", "0"},
      # HeartBtInt (30 seconds)
      {"108", "30"},
      # ResetSeqNumFlag (Reset sequence numbers)
      {"141", "Y"}
    ]
  end

end
