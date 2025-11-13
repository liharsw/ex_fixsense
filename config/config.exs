import Config

# ExFixsense Session Configurations
#
# Define FIX sessions here with broker-specific settings.
# Each session can have its own logon strategy, transport, and protocol version.

config :ex_fixsense, :sessions,
  # Example: Cumberland Order Entry Session
  # Replace placeholder values with your actual credentials from Cumberland
  cumberland_oe: [
    host: "fix-cumberlandmining.internal",
    port: 24001,
    protocol_version: "FIX.4.4",
    transport: ExFixsense.Transport.SSL,

    # Session identifiers - REPLACE WITH YOUR VALUES
    sender_comp_id: "your-sender-comp-id-uuid-here",
    sender_sub_id: "your-sender-sub-id-here",
    target_comp_id: "cumberland",

    # Logon strategy (OnBehalfOf for Cumberland)
    logon_strategy: ExFixsense.Logon.OnBehalfOf,
    logon_fields: %{
      on_behalf_of_comp_id: "your-on-behalf-of-comp-id-uuid-here",
      on_behalf_of_sub_id: "your-on-behalf-of-sub-id-here"
    },

    # SSL options - REPLACE WITH YOUR CERTIFICATE PATHS
    ssl_opts: [
      certfile: Path.expand("../certs/cumberland-client.crt", __DIR__),
      keyfile: Path.expand("../certs/cumberland-client.key", __DIR__),
      cacertfile: Path.expand("../certs/ca.crt", __DIR__),
      verify: :verify_peer,
      versions: [:"tlsv1.2"],
      server_name_indication: ~c"fix-cumberlandmining.internal"
    ]
  ],

  # Example: Cumberland Market Data Session
  # Replace placeholder values with your actual credentials from Cumberland
  cumberland_md: [
    host: "fix-cumberlandmining.internal",
    port: 24001,
    protocol_version: "FIX.4.4",
    transport: ExFixsense.Transport.SSL,

    # Session identifiers - REPLACE WITH YOUR VALUES
    sender_comp_id: "your-sender-comp-id-uuid-here",
    sender_sub_id: "your-sender-sub-id-here",
    target_comp_id: "cumberland",

    # Logon strategy
    logon_strategy: ExFixsense.Logon.OnBehalfOf,
    logon_fields: %{
      on_behalf_of_comp_id: "your-on-behalf-of-comp-id-uuid-here",
      on_behalf_of_sub_id: "your-on-behalf-of-sub-id-here"
    },

    # SSL options - REPLACE WITH YOUR CERTIFICATE PATHS
    ssl_opts: [
      certfile: Path.expand("../certs/cumberland-client.crt", __DIR__),
      keyfile: Path.expand("../certs/cumberland-client.key", __DIR__),
      cacertfile: Path.expand("../certs/ca.crt", __DIR__),
      verify: :verify_peer,
      versions: [:"tlsv1.2"],
      server_name_indication: ~c"fix-cumberlandmining.internal"
    ]
  ],

  # Example: Coinbase Session (for reference)
  coinbase: [
    host: "fix.coinbase.com",
    port: 4198,
    protocol_version: "FIX.4.2",
    transport: ExFixsense.Transport.TCP,
    sender_comp_id: "MY_FIRM",
    target_comp_id: "Coinbase",

    # Username/Password logon
    logon_strategy: ExFixsense.Logon.UsernamePassword,
    logon_fields: %{
      username: System.get_env("COINBASE_API_KEY", ""),
      password: System.get_env("COINBASE_API_SECRET", "")
    }
  ],

  # Example: Generic Broker with Standard Logon
  generic_broker: [
    host: "fix.example.com",
    port: 9876,
    protocol_version: "FIX.4.4",
    transport: ExFixsense.Transport.SSL,
    sender_comp_id: "MY_FIRM",
    target_comp_id: "BROKER",

    # Standard logon (SSL certificate auth only)
    logon_strategy: ExFixsense.Logon.Standard,
    ssl_opts: [
      certfile: "certs/client.crt",
      keyfile: "certs/client.key"
    ]
  ]

# Import environment-specific config
#
# Uncomment to load environment-specific configurations:
# import_config "#{config_env()}.exs"
