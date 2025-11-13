defmodule ExFixsense.Logon.Behaviour do
  @moduledoc """
  Behavior for FIX logon strategies.

  Different brokers require different authentication methods.
  Implement this behavior to support a new broker's logon requirements.

  ## Callbacks

  - `build_logon_fields/1` - Returns fields to add to the logon message (MsgType=A)

  ## Examples

  ### Standard Logon (No special auth)

      defmodule MyApp.StandardLogon do
        @behaviour ExFixsense.Logon.Behaviour

        def build_logon_fields(_config) do
          [
            {"98", "0"},   # EncryptMethod
            {"108", "30"}, # HeartBtInt
            {"141", "Y"}   # ResetSeqNumFlag
          ]
        end
      end

  ### Custom Authentication

      defmodule MyApp.CustomLogon do
        @behaviour ExFixsense.Logon.Behaviour

        def build_logon_fields(config) do
          [
            {"98", "0"},
            {"108", "30"},
            {"553", config.api_key},
            {"554", generate_signature(config)}
          ]
        end
      end

  ## Usage in Configuration

      config :ex_fixsense, :sessions,
        my_broker: [
          logon_strategy: MyApp.CustomLogon,
          logon_fields: %{
            api_key: "...",
            secret: "..."
          }
        ]
  """

  @doc """
  Build fields to add to the logon message (MsgType=A).

  This is called when the session is connecting to the broker.
  Return a list of {tag, value} tuples to add to the logon message.

  ## Parameters

  - `config` - Session configuration map containing logon_fields and other settings

  ## Returns

  List of {tag, value} tuples, e.g.:
  ```
  [
    {"98", "0"},    # EncryptMethod
    {"108", "30"},  # HeartBtInt
    {"141", "Y"},   # ResetSeqNumFlag
    {"553", "user"} # Username (example)
  ]
  ```

  ## Note

  Standard fields like BeginString (8), MsgType (35), SenderCompID (49), etc.
  are added automatically by the session. Only return strategy-specific fields.
  """
  @callback build_logon_fields(config :: map()) :: [{String.t(), String.t()}]

end
