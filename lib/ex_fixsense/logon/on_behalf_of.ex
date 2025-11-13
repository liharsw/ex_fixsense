defmodule ExFixsense.Logon.OnBehalfOf do
  @moduledoc """
  OnBehalfOf FIX logon strategy.

  Used by Cumberland Mining and other institutional brokers that require
  OnBehalfOf fields (Tag 115, 116) for authentication and authorization.

  ## Important: OnBehalfOf Field Placement

  **Critical:** Per FIX spec and Cumberland API documentation (line 86),
  OnBehalfOf fields are **NOT** included in the logon message.

  From Cumberland docs:
  > "These headers must be set on all Application messages, but are
  > **not required on Administrative messages** such as Logon, Logout, Heartbeat etc."

  Therefore:
  - `build_logon_fields/1` does NOT include Tag 115/116
  - **You must manually add Tags 115/116 to each application message**

  ## FIX Tags

  - Tag 115 (OnBehalfOfCompID): Counterparty ID (UUID)
  - Tag 116 (OnBehalfOfSubID): User ID

  ## When to Use

  - Cumberland Mining FIX API
  - Institutional brokers requiring counterparty/user identification
  - Multi-tenant trading platforms
  - Brokers with sub-account structures

  ## Configuration Example

      config :ex_fixsense, :sessions,
        cumberland_oe: [
          host: "fix-cumberlandmining.internal",
          port: 24001,
          protocol_version: "FIX.4.4",
          transport: ExFixsense.Transport.SSL,

          # Use OnBehalfOf logon strategy
          logon_strategy: ExFixsense.Logon.OnBehalfOf,

          # OnBehalfOf credentials
          logon_fields: %{
            on_behalf_of_comp_id: "a9def498-5bf7-422f-975b-9c67f444930c",
            on_behalf_of_sub_id: "tennet_cce"
          },

          sender_comp_id: "c76d28d1-85d0-4991-96c8-25b8b408250a",
          sender_sub_id: "tennet-oe-01",
          target_comp_id: "cumberland",

          ssl_opts: [
            certfile: "certs/cumberland-client.crt",
            keyfile: "certs/cumberland-client.key",
            cacertfile: "certs/ca.crt"
          ]
        ]

  ## Usage

      # Start Cumberland session
      {:ok, pid} = ExFixsense.start_session(
        "cumberland-oe",
        :cumberland_oe,
        MyCumberlandHandler
      )

      # When sending application messages, manually add OnBehalfOf fields:
      #
      # message = %OutMessage{
      #   msg_type: "D",
      #   fields: [
      #     {"115", "a9def498-5bf7-422f-975b-9c67f444930c"},  # OnBehalfOfCompID
      #     {"116", "tennet_cce"},                           # OnBehalfOfSubID
      #     {"55", "BTC-USD"},
      #     {"54", "1"},
      #     # ... other fields
      #   ]
      # }
      # ExFixsense.send_message("cumberland-oe", message)

  ## Authentication Flow

  1. **Logon (Administrative Message):**
     - Session connects with SSL client certificate
     - Logon message sent WITHOUT OnBehalfOf fields
     - Authenticated via certificate + SenderCompID/SenderSubID

  2. **Application Messages (Orders, Market Data, etc.):**
     - User manually adds Tag 115 (OnBehalfOfCompID) to message fields
     - User manually adds Tag 116 (OnBehalfOfSubID) to message fields
     - Identifies which counterparty/user is making the request

  ## OnBehalfOf Fields

  For Cumberland, store these credentials in your config:
  - `:on_behalf_of_comp_id` - Counterparty ID (UUID from Cumberland)
  - `:on_behalf_of_sub_id` - User ID

  You'll manually add these as Tag 115/116 when sending messages.

  ## References

  - Cumberland API 2.0 Documentation, line 86
  - FIX Protocol Specification 4.4
  """

  @behaviour ExFixsense.Logon.Behaviour

  @impl true
  def build_logon_fields(_config) do
    [
      # EncryptMethod (None - using SSL)
      {"98", "0"},
      # HeartBtInt (30 seconds)
      {"108", "30"},
      # ResetSeqNumFlag
      {"141", "Y"}

      # NO OnBehalfOf fields here!
      # Per Cumberland docs line 86:
      # "not required on Administrative messages such as Logon, Logout, Heartbeat"
    ]
  end

end
