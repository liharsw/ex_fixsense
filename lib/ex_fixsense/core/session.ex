defmodule ExFixsense.Core.Session do
  @moduledoc """
  GenServer managing a single FIX protocol session.

  Each session maintains:
  - Persistent TCP/SSL connection to broker
  - Logon state and heartbeat monitoring
  - Message sequence numbers (send and receive)
  - Message routing to handler callbacks

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │                      Your Application                        │
  │                                                              │
  │  ┌──────────────────┐          ┌──────────────────┐        │
  │  │ MarketDataHandler│          │ OrderEntryHandler│        │
  │  └────────┬─────────┘          └────────┬─────────┘        │
  │           │                              │                  │
  │           │ implements                   │ implements       │
  │           │ SessionHandler               │ SessionHandler   │
  │           │                              │                  │
  └───────────┼──────────────────────────────┼──────────────────┘
              │                              │
              ▼                              ▼
  ┌───────────────────────────────────────────────────────────┐
  │              ExFixsense.Core.Session (this module)         │
  │                                                            │
  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐  │
  │  │ Connection  │  │  Heartbeat   │  │  Message Router │  │
  │  │  Manager    │  │   Monitor    │  │                 │  │
  │  └─────────────┘  └──────────────┘  └─────────────────┘  │
  │                                                            │
  │  ┌─────────────┐  ┌──────────────┐                        │
  │  │   Logon     │  │   SeqNum     │                        │
  │  │  Strategy   │  │   Tracker    │                        │
  │  └─────────────┘  └──────────────┘                        │
  └───────────┬───────────────────────────────────────────────┘
              │
              │ SSL/TCP
              │
              ▼
  ┌───────────────────────────────────────────────────────────┐
  │                    FIX Broker Server                       │
  │            (Cumberland, Coinbase, etc.)                    │
  └───────────────────────────────────────────────────────────┘
  ```

  ## Usage

      # Start a session with config from config.exs
      {:ok, pid} = ExFixsense.Core.Session.start_link(
        session_key: :cumberland_md,
        handler: MyApp.MarketDataHandler,
        handler_state: %{}
      )

      # Send a message
      message = ExFixsense.Message.Builder.new("V")  # MarketDataRequest
      |> ExFixsense.Message.Builder.set_field("262", "SUB-001")
      ExFixsense.Core.Session.send_message(:cumberland_md, message)

      # Stop session
      ExFixsense.Core.Session.stop(:cumberland_md)

  ## State Machine

  The session goes through these states:

  1. **disconnected** - Initial state, no connection
  2. **connecting** - Opening TCP/SSL connection
  3. **connected** - Connection established, sending logon
  4. **logged_on** - Logon successful, ready for business messages
  5. **logging_out** - Logout sent, waiting for response
  6. **disconnected** - Connection closed

  ## Heartbeat Monitoring

  Per FIX 4.4 spec, both sides must send heartbeats:
  - Send heartbeat every N seconds (from config HeartBtInt)
  - Expect heartbeat from server within N seconds
  - If no message received in N seconds, send TestRequest
  - If no response to TestRequest, disconnect

  ## Sequence Numbers

  FIX requires strict sequence numbering:
  - MsgSeqNum (tag 34) increments for each sent message
  - Both sides track their own send sequence
  - On reconnect with ResetSeqNumFlag=Y, sequences reset to 1

  ## Message Sending

  The session only adds standard FIX headers (BeginString, MsgType, MsgSeqNum,
  SenderCompID, TargetCompID, SendingTime). Users must manually add all
  application-specific fields, including OnBehalfOf (Tag 115/116) for brokers
  like Cumberland.
  """

  use GenServer
  require Logger

  alias ExFixsense.Core.Config
  alias ExFixsense.Message.{OutMessage, InMessage}
  alias ExFixsense.Protocol.{MessageBuilder, MessageParser, Utilities, Parser}

  @type session_key :: atom()
  @type handler_module :: module()

  # Client API

  @doc """
  Start a FIX session GenServer.

  ## Options

  - `:session_key` (required) - Atom identifying this session (e.g., `:cumberland_md`)
  - `:handler` (required) - Module implementing `ExFixsense.SessionHandler`
  - `:handler_state` (optional) - Initial state passed to handler callbacks (default: `%{}`)

  ## Returns

  `{:ok, pid}` or `{:error, reason}`

  ## Example

      {:ok, pid} = ExFixsense.Core.Session.start_link(
        session_key: :cumberland_md,
        handler: MyApp.MarketDataHandler,
        handler_state: %{subscriptions: []}
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session_key = Keyword.fetch!(opts, :session_key)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {ExFixsense.SessionRegistry, session_key}}
    )
  end

  @doc """
  Send a FIX message through this session.

  The message will have standard fields automatically added:
  - BeginString (8) = FIX.4.4
  - SenderCompID (49) from config
  - TargetCompID (56) from config
  - SendingTime (52) = current UTC timestamp
  - MsgSeqNum (34) = next sequence number
  - OnBehalfOf fields (115/116) if required by logon strategy

  ## Parameters

  - `session_key` - Atom identifying the session
  - `message` - `%OutMessage{}` built with `ExFixsense.Message.Builder`

  ## Returns

  - `{:ok, raw_fix_message}` - Message sent successfully, returns the raw FIX message as pipe-delimited string
  - `{:error, :session_not_found}` - Session not running
  - `{:error, :not_logged_on}` - Session not yet logged on
  - `{:error, reason}` - Other send errors

  ## Example

      message =
        Builder.new("D")  # NewOrderSingle
        |> Builder.set_field("11", "ORDER-001")
        |> Builder.set_field("55", "BTC-USD")
        |> Builder.set_field("54", "1")
        |> Builder.set_field("38", "1.5")

      {:ok, raw_fix} = ExFixsense.Core.Session.send_message(:cumberland_oe, message)
      # raw_fix = "8=FIX.4.4|9=123|35=D|49=SENDER|56=TARGET|34=5|52=20250116-12:00:00|11=ORDER-001|...|10=234|"
  """
  @spec send_message(session_key(), OutMessage.t()) :: {:ok, binary()} | {:error, term()}
  def send_message(session_key, %OutMessage{} = message) do
    case Registry.lookup(ExFixsense.SessionRegistry, session_key) do
      [{pid, _}] -> GenServer.call(pid, {:send_message, message})
      [] -> {:error, :session_not_found}
    end
  end

  @doc """
  Stop a FIX session gracefully.

  Sends logout message and closes connection.

  ## Parameters

  - `session_key` - Atom identifying the session

  ## Returns

  `:ok`
  """
  @spec stop(session_key()) :: :ok
  def stop(session_key) do
    case Registry.lookup(ExFixsense.SessionRegistry, session_key) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> :ok
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    session_key = Keyword.fetch!(opts, :session_key)
    handler = Keyword.fetch!(opts, :handler)
    handler_state = Keyword.get(opts, :handler_state, %{})

    # Load config from application environment
    {:ok, config} = Config.get(session_key)

    # Validate handler implements behavior
    unless function_exported?(handler, :on_logon, 2) do
      raise ArgumentError, "Handler #{inspect(handler)} must implement ExFixsense.SessionHandler"
    end

    state = %{
      session_key: session_key,
      handler: handler,
      handler_state: handler_state,
      config: config,
      socket: nil,
      status: :disconnected,
      send_seq_num: 1,
      recv_seq_num: 1,
      last_send_time: nil,
      last_recv_time: nil,
      heartbeat_ref: nil,
      buffer: ""
    }

    # Start connection asynchronously
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("[#{state.session_key}] Connecting to #{state.config.host}:#{state.config.port}")

    case connect_socket(state.config) do
      {:ok, socket} ->
        Logger.info("[#{state.session_key}] Connected, sending logon")
        new_state = %{state | socket: socket, status: :connected}

        # Send logon message
        case send_logon(new_state) do
          {:ok, new_state_after_logon} ->
            # Start listening for messages
            setopts(socket, state.config, active: :once)

            # Start heartbeat timer
            heartbeat_interval =
              String.to_integer(Map.get(state.config, :heartbeat_interval, "30"))

            heartbeat_ref = Process.send_after(self(), :heartbeat, heartbeat_interval * 1000)

            {:noreply,
             %{
               new_state_after_logon
               | heartbeat_ref: heartbeat_ref,
                 last_send_time: DateTime.utc_now()
             }}

          {:error, reason} ->
            Logger.error("[#{state.session_key}] Failed to send logon: #{inspect(reason)}")
            :ssl.close(socket)
            # Retry connection after 5 seconds
            Process.send_after(self(), :connect, 5_000)
            {:noreply, %{state | socket: nil, status: :disconnected}}
        end

      {:error, reason} ->
        Logger.error("[#{state.session_key}] Connection failed: #{inspect(reason)}")
        # Retry connection after 5 seconds
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ssl, socket, data}, state) do
    # Continue receiving
    setopts(socket, state.config, active: :once)

    # Update last receive time
    new_state = %{state | last_recv_time: DateTime.utc_now()}

    # Append to buffer (might receive partial messages)
    buffered_data = state.buffer <> data

    # Convert SOH to readable format
    readable_data = MessageParser.to_readable(buffered_data)

    # Split into individual messages
    messages = MessageParser.split(readable_data)

    # Process complete messages, keep incomplete in buffer
    {complete_messages, remaining_buffer} =
      if String.ends_with?(readable_data, "|") do
        {messages, ""}
      else
        # Last message is incomplete, keep it in buffer
        {Enum.drop(messages, -1), List.last(messages) || ""}
      end

    # Process each complete message
    final_state =
      Enum.reduce(complete_messages, new_state, fn message, acc_state ->
        case handle_incoming_message(message, acc_state) do
          {:ok, updated_state} ->
            updated_state

          {:error, reason} ->
            Logger.error("[#{state.session_key}] Error processing message: #{inspect(reason)}")
            acc_state
        end
      end)

    {:noreply, %{final_state | buffer: remaining_buffer}}
  end

  @impl true
  def handle_info({:ssl_closed, _socket}, state) do
    Logger.warning("[#{state.session_key}] Connection closed by server", [])

    # Notify handler
    invoke_handler(state, :on_logout, [
      state.session_key,
      {:connection_lost, :closed},
      state.config
    ])

    # Cancel heartbeat timer
    if state.heartbeat_ref, do: Process.cancel_timer(state.heartbeat_ref)

    # Attempt reconnect
    Process.send_after(self(), :connect, 5_000)

    {:noreply, %{state | socket: nil, status: :disconnected, heartbeat_ref: nil}}
  end

  @impl true
  def handle_info({:ssl_error, _socket, reason}, state) do
    Logger.error("[#{state.session_key}] SSL error: #{inspect(reason)}")

    # Notify handler
    invoke_handler(state, :on_logout, [
      state.session_key,
      {:connection_lost, reason},
      state.config
    ])

    # Cancel heartbeat timer
    if state.heartbeat_ref, do: Process.cancel_timer(state.heartbeat_ref)

    # Attempt reconnect
    Process.send_after(self(), :connect, 5_000)

    {:noreply, %{state | socket: nil, status: :disconnected, heartbeat_ref: nil}}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Check if we need to send heartbeat
    now = DateTime.utc_now()
    heartbeat_interval = String.to_integer(Map.get(state.config, :heartbeat_interval, "30"))

    new_state =
      if state.last_send_time && DateTime.diff(now, state.last_send_time) >= heartbeat_interval do
        # Send heartbeat
        case send_heartbeat(state) do
          {:ok, updated_state} ->
            Logger.debug("[#{state.session_key}] Sent heartbeat")
            updated_state

          {:error, reason} ->
            Logger.error("[#{state.session_key}] Failed to send heartbeat: #{inspect(reason)}")
            state
        end
      else
        state
      end

    # Schedule next heartbeat check
    heartbeat_ref = Process.send_after(self(), :heartbeat, heartbeat_interval * 1000)

    {:noreply, %{new_state | heartbeat_ref: heartbeat_ref}}
  end

  @impl true
  def handle_call({:send_message, message}, _from, state) do
    if state.status != :logged_on do
      {:reply, {:error, :not_logged_on}, state}
    else
      case send_app_message(message, state) do
        {:ok, new_state, raw_fix} -> {:reply, {:ok, raw_fix}, new_state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  # Private Functions

  defp setopts(socket, config, opts) do
    # Use :ssl.setopts for SSL sockets, :inet.setopts for TCP
    transport = Map.get(config, :transport, ExFixsense.Transport.SSL)

    case transport do
      ExFixsense.Transport.SSL -> :ssl.setopts(socket, opts)
      _ -> :inet.setopts(socket, opts)
    end
  end

  defp connect_socket(config) do
    host = String.to_charlist(config.host)
    port = config.port

    ssl_opts = Map.get(config, :ssl_opts, [])
    # Default SSL options
    default_opts = [
      verify: :verify_none,
      active: false,
      packet: :raw,
      mode: :binary
    ]

    opts = Keyword.merge(default_opts, ssl_opts)

    :ssl.connect(host, port, opts, 10_000)
  end

  defp send_logon(state) do
    # Get logon strategy module
    logon_strategy = Map.fetch!(state.config, :logon_strategy)

    # Build logon fields from strategy
    strategy_fields = logon_strategy.build_logon_fields(state.config)

    # Check if ResetSeqNumFlag=Y is in strategy fields
    reset_flag = Enum.find_value(strategy_fields, "N", fn
      {"141", val} -> val
      _ -> nil
    end)

    # Reset send_seq_num if we're resetting sequences
    state = if reset_flag == "Y" do
      Logger.info("[#{state.session_key}] Resetting send sequence to 1 (ResetSeqNumFlag=Y)")
      %{state | send_seq_num: 1}
    else
      state
    end

    # Build logon message with correct FIX header order
    # Order: 8, 35, 49, 56, 34, 50 (optional), 52
    fields = [
      {"8", state.config.protocol_version},
      {"35", "A"},
      {"49", state.config.sender_comp_id},
      {"56", state.config.target_comp_id},
      {"34", "#{state.send_seq_num}"}
    ]

    # Add SenderSubID if present (inline with other headers)
    fields =
      if sender_sub_id = Map.get(state.config, :sender_sub_id) do
        fields ++ [{"50", sender_sub_id}]
      else
        fields
      end

    # Add SendingTime
    fields = fields ++ [{"52", Utilities.utc_timestamp()}]

    # Add strategy fields
    fields = fields ++ strategy_fields

    # Build and send
    message_binary = MessageBuilder.build(fields)

    case :ssl.send(state.socket, message_binary) do
      :ok ->
        Logger.debug(
          "[#{state.session_key}] Sent logon: #{MessageParser.to_readable(message_binary)}"
        )

        {:ok, %{state | send_seq_num: state.send_seq_num + 1}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_heartbeat(state) do
    # Build heartbeat message with correct FIX header order
    # Order: 8, 35, 49, 56, 34, 50 (optional), 52
    fields = [
      {"8", state.config.protocol_version},
      {"35", "0"},
      {"49", state.config.sender_comp_id},
      {"56", state.config.target_comp_id},
      {"34", "#{state.send_seq_num}"}
    ]

    # Add SenderSubID if present (inline with other headers)
    fields =
      if sender_sub_id = Map.get(state.config, :sender_sub_id) do
        fields ++ [{"50", sender_sub_id}]
      else
        fields
      end

    # Add SendingTime
    fields = fields ++ [{"52", Utilities.utc_timestamp()}]

    message_binary = MessageBuilder.build(fields)

    case :ssl.send(state.socket, message_binary) do
      :ok ->
        {:ok, %{state | send_seq_num: state.send_seq_num + 1, last_send_time: DateTime.utc_now()}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_app_message(message, state) do
    # Build header fields with correct FIX header order
    # Order: 8, 35, 49, 56, 34, 50 (optional), 52
    base_fields = [
      {"8", state.config.protocol_version},
      {"35", message.msg_type},
      {"49", state.config.sender_comp_id},
      {"56", state.config.target_comp_id},
      {"34", "#{state.send_seq_num}"}
    ]

    # Add SenderSubID if present (inline with other headers)
    base_fields =
      if sender_sub_id = Map.get(state.config, :sender_sub_id) do
        base_fields ++ [{"50", sender_sub_id}]
      else
        base_fields
      end

    # Add SendingTime
    base_fields = base_fields ++ [{"52", Utilities.utc_timestamp()}]

    # Add message fields (user provides all application-specific fields)
    message_fields =
      Enum.flat_map(message.fields, fn {tag, value} ->
        case value do
          list when is_list(list) -> Enum.map(list, fn v -> {tag, v} end)
          _ -> [{tag, value}]
        end
      end)

    all_fields = base_fields ++ message_fields

    # Build and send
    message_binary = MessageBuilder.build(all_fields)
    readable_fix = MessageParser.to_readable(message_binary)

    case :ssl.send(state.socket, message_binary) do
      :ok ->
        Logger.debug("[#{state.session_key}] Sent: #{readable_fix}")
        {:ok, %{state | send_seq_num: state.send_seq_num + 1, last_send_time: DateTime.utc_now()}, readable_fix}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_incoming_message(message_str, state) do
    # Validate and parse message into InMessage struct
    case Parser.validate_and_parse(message_str) do
      {:ok, %InMessage{} = msg} ->
        Logger.debug("[#{state.session_key}] Received: #{msg.msg_type} seqnum: #{msg.seqnum}")

        # Special handling for Logon message with ResetSeqNumFlag=Y
        # Must reset recv_seq_num BEFORE sequence validation
        state = if msg.msg_type == "A" do
          fields = Parser.fields_to_map(msg)
          reset_flag = Map.get(fields, "141", "N")

          if reset_flag == "Y" do
            Logger.info("[#{state.session_key}] Resetting recv sequence to 1 (server sent ResetSeqNumFlag=Y)")
            %{state | recv_seq_num: 1}
          else
            state
          end
        else
          state
        end

        cond do
          msg.seqnum > state.recv_seq_num ->
            # Sequence gap detected - notify user, let them decide what to do
            Logger.warning("[#{state.session_key}] Sequence gap: expected #{state.recv_seq_num}, got #{msg.seqnum}", [])
            invoke_handler(state, :on_session_message, [state.session_key, msg, state.config])
            {:ok, state}  # Don't update recv_seq_num - user handles gap

          msg.seqnum < state.recv_seq_num ->
            # Possible duplicate - ignore
            Logger.debug("[#{state.session_key}] Possible duplicate: expected #{state.recv_seq_num}, got #{msg.seqnum}")
            {:ok, state}

          true ->
            # Normal message - update sequence and route
            new_state = %{state | recv_seq_num: state.recv_seq_num + 1}
            route_message(msg, new_state)
        end

      {:error, reason} ->
        # Validation failed - reject message
        Logger.error("[#{state.session_key}] Invalid message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Extract existing routing logic
  defp route_message(%InMessage{} = msg, state) do
    case msg.msg_type do
      # Library handles (FIX protocol requirements)
      "A" -> handle_logon_response(msg, state)
      "0" -> {:ok, state}  # Heartbeat - ignore
      "1" -> handle_test_request(msg, state)  # TestRequest - FIX requires Heartbeat response
      "4" -> handle_sequence_reset(msg, state)  # SequenceReset - FIX defines behavior
      "5" -> handle_logout(msg, state)

      # Session messages - user handles via on_session_message
      "2" ->  # ResendRequest - user decides how to resend
        invoke_handler(state, :on_session_message, [state.session_key, msg, state.config])
        {:ok, state}

      "3" ->  # Reject - user decides how to handle error
        invoke_handler(state, :on_session_message, [state.session_key, msg, state.config])
        {:ok, state}

      # Application messages - user handles via on_app_message
      _ ->
        invoke_handler(state, :on_app_message, [state.session_key, msg, state.config])
        {:ok, state}
    end
  end

  defp handle_logon_response(%InMessage{}, state) do
    # Note: recv_seq_num reset is handled in handle_incoming_message before this is called
    Logger.info("[#{state.session_key}] Logon successful")

    # Notify handler
    invoke_handler(state, :on_logon, [state.session_key, state.config])

    {:ok, %{state | status: :logged_on}}
  end

  defp handle_test_request(%InMessage{} = msg, state) do
    # Convert to map to get TestReqID
    fields = Parser.fields_to_map(msg)
    test_req_id = Map.get(fields, "112", "")

    # Send Heartbeat with TestReqID - correct FIX header order
    # Order: 8, 35, 49, 56, 34, 50 (optional), 52, then body fields (112)
    response_fields = [
      {"8", state.config.protocol_version},
      {"35", "0"},
      {"49", state.config.sender_comp_id},
      {"56", state.config.target_comp_id},
      {"34", "#{state.send_seq_num}"}
    ]

    # Add SenderSubID if present (inline with other headers)
    response_fields =
      if sender_sub_id = Map.get(state.config, :sender_sub_id) do
        response_fields ++ [{"50", sender_sub_id}]
      else
        response_fields
      end

    # Add SendingTime and body fields
    response_fields = response_fields ++ [
      {"52", Utilities.utc_timestamp()},
      {"112", test_req_id}
    ]

    message_binary = MessageBuilder.build(response_fields)

    case :ssl.send(state.socket, message_binary) do
      :ok ->
        Logger.debug("[#{state.session_key}] Sent heartbeat in response to TestRequest")
        {:ok, %{state | send_seq_num: state.send_seq_num + 1, last_send_time: DateTime.utc_now()}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_logout(%InMessage{} = msg, state) do
    # Convert to map to get Text field
    fields = Parser.fields_to_map(msg)
    text = Map.get(fields, "58", "")
    Logger.info("[#{state.session_key}] Received logout: #{text}")

    # Notify handler
    invoke_handler(state, :on_logout, [state.session_key, {:logout, text}, state.config])

    # Close socket
    if state.socket, do: :ssl.close(state.socket)

    {:ok, %{state | status: :disconnected, socket: nil}}
  end

  # SequenceReset Handler
  defp handle_sequence_reset(%InMessage{} = msg, state) do
    # Convert to map to get fields
    fields = Parser.fields_to_map(msg)
    gap_fill_flag = Map.get(fields, "123", "N")
    new_seq_no = String.to_integer(Map.get(fields, "36"))

    if gap_fill_flag == "Y" do
      Logger.info("[#{state.session_key}] SequenceReset-GapFill: setting next expected to #{new_seq_no}")
      {:ok, %{state | recv_seq_num: new_seq_no}}
    else
      Logger.warning("[#{state.session_key}] SequenceReset-HardReset: resetting sequence to #{new_seq_no}", [])
      {:ok, %{state | recv_seq_num: new_seq_no}}
    end
  end

  defp invoke_handler(state, callback, args) do
    try do
      apply(state.handler, callback, args)
    rescue
      e ->
        Logger.error("[#{state.session_key}] Handler error in #{callback}: #{inspect(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
    end
  end
end
