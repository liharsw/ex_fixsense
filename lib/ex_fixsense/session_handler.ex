defmodule ExFixsense.SessionHandler do
  @moduledoc """
  Behavior for handling FIX session events.

  Implement this behavior to create custom handlers for different session types
  (market data, order entry, etc.).

  ## Callbacks

  - `on_logon/2` - Called when logon is successful
  - `on_app_message/3` - Called when application message is received
  - `on_session_message/3` - Called when session-level message is received
  - `on_logout/3` - Called when logout is received or connection is lost

  ## Example: Market Data Handler

      defmodule MyApp.MarketDataHandler do
        @behaviour ExFixsense.SessionHandler

        def on_logon(session_key, config) do
          IO.puts "Connected to \#{config.host}:\#{config.port}"

          # Subscribe to market data
          message =
            ExFixsense.Message.Builder.new("V")  # MarketDataRequest
            |> ExFixsense.Message.Builder.set_field("262", "MD-SUB-001")
            |> ExFixsense.Message.Builder.set_field("263", "1")  # Subscription
            |> ExFixsense.Message.Builder.set_field("264", "1")  # Full refresh
            |> ExFixsense.Message.Builder.set_field("267", "2")  # 2 MDEntryTypes
            |> ExFixsense.Message.Builder.set_field("269", "0")  # Bid
            |> ExFixsense.Message.Builder.set_field("269", "1")  # Offer
            |> ExFixsense.Message.Builder.set_field("146", "1")  # 1 symbol
            |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")

          ExFixsense.send_message(session_key, message)
        end

        def on_app_message(session_key, msg, _config) do
          # Convert fields to map when needed
          fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

          case msg.msg_type do
            "W" ->  # MarketDataSnapshotFullRefresh
              symbol = Map.get(fields, "55")
              IO.puts "Market data for \#{symbol}: \#{inspect(fields)}"

            "X" ->  # MarketDataIncrementalRefresh
              IO.puts "Market data update: \#{inspect(fields)}"

            _ ->
              IO.puts "Received app message \#{msg.msg_type}: \#{inspect(fields)}"
          end
        end

        def on_session_message(session_key, msg, _config) do
          case msg.msg_type do
            "0" -> :ok  # Heartbeat
            "1" -> :ok  # TestRequest (handled by core session)
            _ ->
              fields = ExFixsense.Protocol.Parser.fields_to_map(msg)
              IO.puts "Session message \#{msg.msg_type}: \#{inspect(fields)}"
          end
        end

        def on_logout(session_key, reason, _config) do
          IO.puts "Session \#{session_key} logged out: \#{reason}"
        end
      end

      # Start the session
      ExFixsense.start_session(:my_md_session, MyApp.MarketDataHandler, %{})

  ## Example: Order Entry Handler

      defmodule MyApp.OrderEntryHandler do
        @behaviour ExFixsense.SessionHandler

        def on_logon(session_key, _config) do
          IO.puts "Order entry session connected"

          # Send a test order
          order =
            ExFixsense.Message.Builder.new("D")  # NewOrderSingle
            |> ExFixsense.Message.Builder.set_field("11", "ORDER-001")
            |> ExFixsense.Message.Builder.set_field("21", "1")  # Manual
            |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")
            |> ExFixsense.Message.Builder.set_field("54", "1")  # Buy
            |> ExFixsense.Message.Builder.set_field("38", "0.1")
            |> ExFixsense.Message.Builder.set_field("40", "1")  # Market

          ExFixsense.send_message(session_key, order)
        end

        def on_app_message(_session_key, msg, _config) do
          # Convert to map to access fields
          fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

          case msg.msg_type do
            "8" ->  # ExecutionReport
              order_id = Map.get(fields, "11")
              status = Map.get(fields, "39")
              IO.puts "Order \#{order_id} status: \#{status}"

            "9" ->  # OrderCancelReject
              IO.puts "Cancel rejected: \#{inspect(fields)}"

            _ ->
              IO.puts "Received app message \#{msg.msg_type}: \#{inspect(fields)}"
          end
        end

        def on_session_message(_session_key, _msg, _config) do
          :ok
        end

        def on_logout(session_key, reason, _config) do
          IO.puts "Order session \#{session_key} logged out: \#{reason}"
        end
      end

  ## Running Multiple Sessions Concurrently

  You can run multiple sessions simultaneously, each with its own handler:

      # Start market data session
      ExFixsense.start_session(:cumberland_md, MyApp.MarketDataHandler, %{})

      # Start order entry session
      ExFixsense.start_session(:cumberland_oe, MyApp.OrderEntryHandler, %{})

  Each session is an independent GenServer process with its own connection,
  heartbeat handling, and message routing.

  ## Handler State

  Handlers are stateless - they are callbacks invoked by the session GenServer.
  If you need to maintain state (e.g., order book, position tracking), you should:

  1. Create a separate GenServer to hold state
  2. Have your handler send messages to that GenServer
  3. Use ETS tables for shared state
  4. Use Agent for simple state storage

  Example with Agent:

      defmodule MyApp.PriceStore do
        def start_link do
          Agent.start_link(fn -> %{} end, name: __MODULE__)
        end

        def update_price(symbol, bid, ask) do
          Agent.update(__MODULE__, fn state ->
            Map.put(state, symbol, %{bid: bid, ask: ask, updated_at: DateTime.utc_now()})
          end)
        end

        def get_price(symbol) do
          Agent.get(__MODULE__, fn state -> Map.get(state, symbol) end)
        end

        def get_all_prices do
          Agent.get(__MODULE__, fn state -> state end)
        end
      end

      defmodule MyApp.MarketDataHandler do
        @behaviour ExFixsense.SessionHandler

        def on_logon(session_key, _config) do
          # Start price store if not already started
          case Process.whereis(MyApp.PriceStore) do
            nil -> MyApp.PriceStore.start_link()
            _pid -> :ok
          end

          # Subscribe to market data...
        end

        def on_app_message(_session_key, msg, _config) when msg.msg_type == "W" do
          fields = ExFixsense.Protocol.Parser.fields_to_map(msg)
          symbol = Map.get(fields, "55")

          # Parse bid/ask from repeating groups
          # (Simplified - real implementation would parse NoMDEntries group)
          bid = Map.get(fields, "bid_price")
          ask = Map.get(fields, "ask_price")

          MyApp.PriceStore.update_price(symbol, bid, ask)
        end

        def on_app_message(_session_key, _msg, _config), do: :ok
        def on_session_message(_session_key, _msg, _config), do: :ok
        def on_logout(_session_key, _reason, _config), do: :ok
      end

  ## Error Handling

  Callbacks should handle errors gracefully. If a callback raises an exception,
  the session GenServer will log the error but continue running.

  Good practice:

      def on_app_message(session_key, msg, config) do
        try do
          # Process message
          handle_message(msg)
        rescue
          e ->
            Logger.error("Error processing message: \#{inspect(e)}")
            :ok
        end
      end

  ## Testing Handlers

  You can test handlers without a live FIX connection:

      test "handles execution report" do
        # Create InMessage for testing
        msg = %ExFixsense.Message.InMessage{
          msg_type: "8",
          seqnum: 42,
          fields: [{"11", "ORDER-001"}, {"39", "2"}, {"151", "0"}],
          valid: true,
          complete: true,
          poss_dup: false,
          original_fix_msg: "",
          error_reason: nil,
          subject: nil,
          other_msgs: "",
          rest_msg: ""
        }

        # Your handler should process this correctly
        MyApp.OrderEntryHandler.on_app_message(:test, msg, %{})

        # Assert side effects (e.g., database updates, notifications)
      end
  """

  @doc """
  Called when the FIX session successfully logs on.

  This is called after the session receives a Logon (35=A) response
  from the server and heartbeat monitoring has started.

  Use this callback to:
  - Subscribe to market data streams
  - Send initial requests
  - Initialize any session-specific state
  - Log connection details

  ## Parameters

  - `session_key` - Atom identifying this session (e.g., `:cumberland_oe`)
  - `config` - Session configuration map from `ExFixsense.Core.Config`

  ## Returns

  Return value is ignored. Use `ExFixsense.send_message/2` to send messages.

  ## Example

      def on_logon(session_key, config) do
        Logger.info("Connected to \#{config.host}:\#{config.port}")

        # Subscribe to market data
        subscribe_request = build_market_data_request()
        ExFixsense.send_message(session_key, subscribe_request)
      end
  """
  @callback on_logon(session_key :: atom(), config :: map()) :: any()

  @doc """
  Called when an application message (non-administrative) is received.

  Application messages are business-level FIX messages like:
  - Market data (35=W, 35=X)
  - Execution reports (35=8)
  - Order cancel rejects (35=9)
  - Position reports (35=AP)

  Administrative messages (heartbeats, TestRequest, Reject, etc.) are
  routed to `on_session_message/3`, not here.

  ## Parameters

  - `session_key` - Atom identifying this session
  - `msg` - InMessage struct containing the parsed FIX message
  - `config` - Session configuration map

  ## InMessage Structure

  The message is provided as an `ExFixsense.Message.InMessage` struct:

      %InMessage{
        msg_type: "W",                                    # String (MsgType tag 35)
        seqnum: 42,                                       # Integer (MsgSeqNum tag 34)
        fields: [{"55", "BTC-USD"}, {"268", "2"}, ...],  # List of {tag, value} tuples
        valid: true,                                      # Boolean
        complete: true,                                   # Boolean
        poss_dup: false,                                  # Boolean (PossDupFlag tag 43)
        original_fix_msg: "8=FIX.4.4|...",               # Binary (raw message)
        # ... other metadata fields
      }

  ## Accessing Fields

  Use `ExFixsense.Protocol.Parser.fields_to_map/1` to convert fields to a map:

      def on_app_message(session_key, msg, config) do
        fields = ExFixsense.Protocol.Parser.fields_to_map(msg)
        symbol = Map.get(fields, "55")
      end

  Or access directly from the list:

      def on_app_message(session_key, msg, config) do
        {_, symbol} = List.keyfind(msg.fields, "55", 0)
      end

  ## Returns

  Return value is ignored.

  ## Example

      def on_app_message(session_key, msg, config) do
        case msg.msg_type do
          "W" ->
            # MarketDataSnapshotFullRefresh
            fields = ExFixsense.Protocol.Parser.fields_to_map(msg)
            handle_snapshot(fields)

          "X" ->
            # MarketDataIncrementalRefresh
            handle_update(msg)

          "8" ->
            # ExecutionReport
            handle_execution(msg)

          _ ->
            Logger.warn("Unhandled message type: \#{msg.msg_type}")
        end
      end
  """
  @callback on_app_message(
              session_key :: atom(),
              msg :: ExFixsense.Message.InMessage.t(),
              config :: map()
            ) :: any()

  @doc """
  Called when a session-level message is received.

  Session-level messages are FIX protocol administrative messages:
  - Heartbeat (35=0) - No action needed
  - TestRequest (35=1) - **Library auto-responds** (no action needed)
  - ResendRequest (35=2) - **You must handle** (resend or send GapFill)
  - Reject (35=3) - **You must handle** (log, alert, disconnect, etc.)
  - SequenceReset (35=4) - **Library auto-handles** (no action needed)

  Also called for:
  - **Sequence gaps** (msg.seqnum > expected) - **You must handle** (send ResendRequest or disconnect)

  Note: Logon (35=A) and Logout (35=5) are handled separately by
  `on_logon/2` and `on_logout/3`.

  ## Library Auto-Handles (Per FIX Spec)

  These are handled automatically because FIX protocol requires it:
  - **TestRequest (35=1)**: Sends Heartbeat with TestReqID
  - **SequenceReset (35=4)**: Updates recv_seq_num per GapFillFlag

  ## You Must Handle

  These require business logic decisions:
  - **ResendRequest (35=2)**: Resend messages or send GapFill (requires MessageStore)
  - **Reject (35=3)**: Log error, send alert, disconnect, etc.
  - **Sequence gaps**: Send ResendRequest or disconnect and reconnect

  ## Parameters

  - `session_key` - Atom identifying this session
  - `msg` - InMessage struct containing the parsed FIX message
  - `config` - Session configuration map

  ## Returns

  Return value is ignored.

  ## Example

      def on_session_message(session_key, msg, config) do
        fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

        case msg.msg_type do
          "0" -> :ok  # Heartbeat - ignore
          "1" -> :ok  # TestRequest - library auto-responds

          "2" ->
            # ResendRequest - send GapFill (MessageStore not implemented)
            end_seq = Map.get(fields, "16")
            gap_fill = ExFixsense.Message.Builder.new("4")
            |> ExFixsense.Message.Builder.set_field("123", "Y")  # GapFillFlag
            |> ExFixsense.Message.Builder.set_field("36", end_seq)  # NewSeqNo
            ExFixsense.send_message(session_key, gap_fill)

          "3" ->
            # Reject - handle error
            Logger.error("FIX Reject: \#{inspect(fields)}")
            # Maybe disconnect and reconnect
            ExFixsense.stop_session(session_key)

          "4" -> :ok  # SequenceReset - library auto-handles

          _ ->
            Logger.debug("Session message \#{msg.msg_type}")
        end
      end
  """
  @callback on_session_message(
              session_key :: atom(),
              msg :: ExFixsense.Message.InMessage.t(),
              config :: map()
            ) :: any()

  @doc """
  Called when the session logs out or loses connection.

  This is called when:
  - Server sends Logout (35=5) message
  - Connection is lost unexpectedly
  - User calls `ExFixsense.stop_session/1`

  Use this callback to:
  - Clean up resources
  - Log disconnection
  - Notify other parts of your application
  - Save state before shutdown

  ## Parameters

  - `session_key` - Atom identifying this session
  - `reason` - Reason for logout:
    - `{:logout, text}` - Server sent logout with optional text
    - `{:connection_lost, reason}` - TCP/SSL connection dropped
    - `:stopped` - User called stop_session/1
  - `config` - Session configuration map

  ## Returns

  Return value is ignored.

  ## Example

      def on_logout(session_key, reason, config) do
        Logger.warn("Session \#{session_key} disconnected: \#{inspect(reason)}")

        # Clean up
        MyApp.SessionMonitor.mark_disconnected(session_key)

        # Optionally attempt reconnect
        if should_reconnect?(reason) do
          Process.send_after(self(), {:reconnect, session_key}, 5_000)
        end
      end
  """
  @callback on_logout(
              session_key :: atom(),
              reason :: term(),
              config :: map()
            ) :: any()
end
