defmodule ExFixsense do
  @moduledoc """
  Generic FIX 4.4 Protocol Library for Elixir.

  ExFixsense provides a broker-agnostic FIX client that works with:
  - Cumberland Mining
  - Coinbase
  - Binance
  - Kraken
  - Any FIX 4.4 broker

  ## Quick Start

  The library provides a clean, handler-based API for managing FIX sessions:

      # Define a handler
      defmodule MyApp.MarketDataHandler do
        @behaviour ExFixsense.SessionHandler

        def on_logon(session_key, _config) do
          # Subscribe to market data
          message = ExFixsense.Message.Builder.new("V")
          |> ExFixsense.Message.Builder.set_field("262", "SUB-001")
          |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")

          ExFixsense.send_message(session_key, message)
          {:ok, %{}}
        end

        def on_app_message(_session_key, "W", fields, state) do
          # Handle market data snapshot
          IO.inspect(fields, label: "Snapshot")
          {:ok, state}
        end

        def on_app_message(_, _, _, state), do: {:ok, state}
        def on_session_message(_, _, _, state), do: {:ok, state}
        def on_logout(_, _, state), do: {:ok, state}
        def on_error(_, error, state) do
          IO.inspect(error, label: "Error")
          {:ok, state}
        end
      end

      # Start session
      {:ok, _pid} = ExFixsense.start_session(:cumberland_md, MyApp.MarketDataHandler)

      # Stop session
      ExFixsense.stop_session(:cumberland_md)

  ## Configuration

  Sessions are configured in `config/config.exs`:

      config :ex_fixsense, :sessions,
        cumberland_md: [
          host: "fix-cumberlandmining.internal",
          port: 24001,
          sender_comp_id: "YOUR_SENDER_ID",
          sender_sub_id: "YOUR_SENDER_SUB_ID",
          target_comp_id: "cumberland",
          logon_strategy: ExFixsense.Logon.OnBehalfOf,
          logon_fields: %{
            on_behalf_of_comp_id: "YOUR_COUNTERPARTY_ID",
            on_behalf_of_sub_id: "YOUR_USER_ID"
          },
          ssl_opts: [
            certfile: "path/to/client.crt",
            keyfile: "path/to/client.key",
            cacertfile: "path/to/ca.crt"
          ]
        ]

  See `ExFixsense.Core.Config` for all configuration options.

  ## See Also

  - `ExFixsense.SessionHandler` - Handler behaviour and callbacks
  - `ExFixsense.Message.Builder` - Fluent API for building FIX messages
  - `ExFixsense.Logon.OnBehalfOf` - Cumberland authentication
  - `ExFixsense.Logon.UsernamePassword` - Coinbase authentication
  - `ExFixsense.Logon.Standard` - Generic authentication
  """

  @doc """
  Start a new FIX session with a custom handler.

  This is the main entry point for the library. It starts a GenServer
  that manages a persistent FIX connection and routes messages to your handler.

  ## Parameters

  - `session_key` - Atom identifying this session (must match a key in config.exs)
  - `handler` - Module implementing `ExFixsense.SessionHandler` behavior
  - `handler_state` - (Optional) Initial state passed to handler callbacks

  ## Returns

  - `{:ok, pid}` - Session started successfully
  - `{:error, reason}` - Failed to start session

  ## Examples

      # Start a market data session
      {:ok, _pid} = ExFixsense.start_session(:cumberland_md, MyApp.MarketDataHandler)

      # Start an order entry session with initial state
      {:ok, _pid} = ExFixsense.start_session(
        :cumberland_oe,
        MyApp.OrderEntryHandler,
        %{orders: []}
      )

  ## Handler Callbacks

  Your handler must implement these callbacks:

  - `on_logon/2` - Called after successful logon
  - `on_app_message/4` - Called for each business message
  - `on_session_message/4` - Called for each session-level message
  - `on_logout/3` - Called when session disconnects
  - `on_error/3` - Called when errors occur

  See `ExFixsense.SessionHandler` for detailed documentation.
  """
  @spec start_session(atom(), module(), any()) :: {:ok, pid()} | {:error, term()}
  def start_session(session_key, handler, handler_state \\ %{}) do
    ExFixsense.Core.Session.start_link(
      session_key: session_key,
      handler: handler,
      handler_state: handler_state
    )
  end

  @doc """
  Send a FIX message through an active session.

  Messages are built using the `ExFixsense.Message.Builder` fluent API.
  Standard fields (BeginString, SenderCompID, MsgSeqNum, etc.) are added
  automatically. OnBehalfOf fields are injected automatically for brokers
  that require them (like Cumberland).

  ## Parameters

  - `session_key` - Atom identifying the session
  - `message` - `%OutMessage{}` built with `ExFixsense.Message.Builder`

  ## Returns

  - `{:ok, raw_fix_message}` - Message sent successfully, returns the raw FIX message as pipe-delimited string
  - `{:error, :session_not_found}` - Session not running
  - `{:error, :not_logged_on}` - Session not yet logged on
  - `{:error, reason}` - Other send errors

  ## Examples

      # Market data subscription
      message =
        ExFixsense.Message.Builder.new("V")  # MarketDataRequest
        |> ExFixsense.Message.Builder.set_field("262", "SUB-001")
        |> ExFixsense.Message.Builder.set_field("263", "1")
        |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")

      {:ok, raw_fix} = ExFixsense.send_message(:cumberland_md, message)
      # raw_fix = "8=FIX.4.4|9=123|35=V|49=SENDER|56=TARGET|34=5|52=20250116-12:00:00|262=SUB-001|...|10=234|"

      # New order
      order =
        ExFixsense.Message.Builder.new("D")  # NewOrderSingle
        |> ExFixsense.Message.Builder.set_field("11", "ORDER-001")
        |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")
        |> ExFixsense.Message.Builder.set_field("54", "1")  # Buy
        |> ExFixsense.Message.Builder.set_field("38", "1.5")  # Quantity
        |> ExFixsense.Message.Builder.set_field("40", "1")  # Market

      {:ok, raw_fix} = ExFixsense.send_message(:cumberland_oe, order)
  """
  @spec send_message(atom(), ExFixsense.Message.OutMessage.t()) :: {:ok, binary()} | {:error, term()}
  def send_message(session_key, message) do
    ExFixsense.Core.Session.send_message(session_key, message)
  end

  @doc """
  Stop a running FIX session gracefully.

  Sends a logout message and closes the connection. The session GenServer
  will terminate.

  ## Parameters

  - `session_key` - Atom identifying the session

  ## Returns

  - `:ok`

  ## Examples

      ExFixsense.stop_session(:cumberland_md)
      ExFixsense.stop_session(:cumberland_oe)
  """
  @spec stop_session(atom()) :: :ok
  def stop_session(session_key) do
    ExFixsense.Core.Session.stop(session_key)
  end
end
