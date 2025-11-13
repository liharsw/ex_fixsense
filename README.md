# ExFixsense

**Minimal, agnostic FIX 4.4 protocol library for Elixir.**

[![Hex.pm](https://img.shields.io/hexpm/v/ex_fixsense.svg)](https://hex.pm/packages/ex_fixsense)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

ExFixsense provides **mechanism, not policy** - you control FIX message handling while the library manages protocol requirements.

## Philosophy

- ✅ **Minimal abstraction** - Library handles FIX protocol, you handle business logic
- ✅ **Broker agnostic** - Works with any FIX 4.4 broker (Cumberland, Coinbase, Binance, etc.)
- ✅ **User control** - You decide how to handle ResendRequest, Reject, sequence gaps

---

## Quick Start

### 1. Installation

```elixir
def deps do
  [{:ex_fixsense, "~> 1.0"}]
end
```

### 2. Configure Session

```elixir
# config/config.exs
config :ex_fixsense, :sessions,
  my_session: [
    host: "fix.broker.com",
    port: 9000,
    sender_comp_id: "YOUR_SENDER_ID",
    target_comp_id: "BROKER",
    logon_strategy: ExFixsense.Logon.Standard,
    ssl_opts: [verify: :verify_none]
  ]
```

### 3. Implement Handler

```elixir
defmodule MyApp.TradingHandler do
  @behaviour ExFixsense.SessionHandler
  require Logger

  def on_logon(session_key, _config) do
    Logger.info("[#{session_key}] Connected!")

    # Send your initial requests here
    request_market_data(session_key)
  end

  def on_app_message(session_key, msg, _config) do
    # Convert fields to map for easy access
    fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

    case msg.msg_type do
      "W" -> handle_market_data_snapshot(session_key, fields)
      "X" -> handle_market_data_update(session_key, fields)
      "8" -> handle_execution_report(session_key, fields)
      "AP" -> handle_position_report(session_key, fields)
      _ -> Logger.debug("[#{session_key}] Unhandled: #{msg.msg_type}")
    end
  end

  def on_session_message(session_key, msg, _config) do
    fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

    case msg.msg_type do
      "0" -> :ok  # Heartbeat - library tracks
      "1" -> :ok  # TestRequest - library auto-responds

      "2" ->
        # ResendRequest - YOU handle this
        end_seq = Map.get(fields, "16")
        Logger.warn("[#{session_key}] ResendRequest - sending GapFill")

        gap_fill = ExFixsense.Message.Builder.new("4")
        |> ExFixsense.Message.Builder.set_field("123", "Y")
        |> ExFixsense.Message.Builder.set_field("36", end_seq)
        ExFixsense.send_message(session_key, gap_fill)

      "3" ->
        # Reject - YOU handle this
        text = Map.get(fields, "58", "")
        Logger.error("[#{session_key}] FIX Reject: #{text}")

      "4" -> :ok  # SequenceReset - library auto-handles
      _ -> :ok
    end
  end

  def on_logout(session_key, reason, _config) do
    Logger.warn("[#{session_key}] Disconnected: #{inspect(reason)}")
  end

  # Your private functions
  defp request_market_data(session_key) do
    message = ExFixsense.Message.Builder.new("V")
    |> ExFixsense.Message.Builder.set_field("262", "MD-#{:os.system_time()}")
    |> ExFixsense.Message.Builder.set_field("263", "1")  # Subscribe
    |> ExFixsense.Message.Builder.set_field("55", "BTC-USD")

    ExFixsense.send_message(session_key, message)
  end

  defp handle_market_data_snapshot(session_key, fields) do
    symbol = Map.get(fields, "55")
    Logger.info("[#{session_key}] Market data: #{symbol}")
    # Update your price store, database, etc.
  end

  defp handle_execution_report(session_key, fields) do
    order_id = Map.get(fields, "11")
    status = Map.get(fields, "39")
    Logger.info("[#{session_key}] Order #{order_id}: status=#{status}")
  end

  # ... other handlers
end
```

### 4. Start Session

```elixir
# In your application supervision tree
{:ok, _pid} = ExFixsense.Core.Session.start_link(
  session_key: :my_session,
  handler: MyApp.TradingHandler,
  handler_state: %{}
)

# Or start directly
ExFixsense.start_session(:my_session, MyApp.TradingHandler)
```

---

## What Library Handles vs You Handle

### ✅ Library Auto-Handles (FIX Protocol Requirements)

These are handled because FIX specification **requires** them:

1. **TestRequest (35=1)** → Auto-sends Heartbeat with TestReqID
2. **SequenceReset (35=4)** → Auto-updates recv_seq_num per GapFillFlag
3. **Logon (35=A)** → Sets session status to :logged_on
4. **Logout (35=5)** → Closes socket
5. **Heartbeat monitoring** → Automatic send/receive
6. **Sequence number tracking** → recv_seq_num, send_seq_num

### ❌ You Handle (Business Logic Decisions)

These require **business decisions**, so you control them:

1. **ResendRequest (35=2)** → Send GapFill or resend messages (requires MessageStore)
2. **Reject (35=3)** → Log error, send alert, disconnect, etc.
3. **Sequence gaps** → Send ResendRequest or disconnect and reconnect
4. **All application messages** → Market data, orders, positions, etc.

---

## Callbacks

### on_logon(session_key, config)

Called when session successfully logs on. Send initial requests here.

**Example**:
```elixir
def on_logon(session_key, _config) do
  # Subscribe to market data
  # Request positions
  # Send any initial messages
end
```

---

### on_app_message(session_key, msg, config)

Called for **all application messages** (market data, orders, positions).

**Parameters**:
- `session_key` - Atom (e.g., `:cumberland_md`)
- `msg` - %InMessage{} struct
- `config` - Session configuration map

**InMessage fields**:
- `msg.msg_type` - String ("W", "8", "AP", etc.)
- `msg.seqnum` - Integer (sequence number)
- `msg.fields` - List of tuples: `[{"55", "BTC-USD"}, {"270", "50000.00"}, ...]`
- `msg.original_fix_msg` - Binary (raw FIX message)
- `msg.valid` - Boolean
- `msg.poss_dup` - Boolean (PossDupFlag)

**Convert to map for easy access**:
```elixir
fields = ExFixsense.Protocol.Parser.fields_to_map(msg)
symbol = Map.get(fields, "55")  # Tag 55 = Symbol
price = Map.get(fields, "270")  # Tag 270 = MDEntryPx
```

---

### on_session_message(session_key, msg, config)

Called for **session messages you must handle**:
- ResendRequest (35=2)
- Reject (35=3)
- Sequence gaps (when msg.seqnum > expected)

Also receives (but library auto-handles):
- Heartbeat (35=0)
- TestRequest (35=1)
- SequenceReset (35=4)

**Example**:
```elixir
def on_session_message(session_key, msg, _config) do
  fields = ExFixsense.Protocol.Parser.fields_to_map(msg)

  case msg.msg_type do
    "2" -> handle_resend_request(session_key, fields)
    "3" -> handle_reject(session_key, fields)
    _ -> :ok
  end
end
```

---

### on_logout(session_key, reason, config)

Called when session disconnects. Clean up resources here.

**Example**:
```elixir
def on_logout(session_key, reason, _config) do
  Logger.warn("Session #{session_key} disconnected: #{inspect(reason)}")
  # Clean up, notify other parts of app, etc.
end
```

---

## Message Building

Use fluent API to build FIX messages:

```elixir
# Market data subscription
message = ExFixsense.Message.Builder.new("V")  # MarketDataRequest
|> ExFixsense.Message.Builder.set_field("262", "MD-#{:os.system_time()}")  # MDReqID
|> ExFixsense.Message.Builder.set_field("263", "1")  # Subscribe
|> ExFixsense.Message.Builder.set_field("264", "1")  # Full book
|> ExFixsense.Message.Builder.set_field("55", "BTC-USD")  # Symbol

ExFixsense.send_message(:my_session, message)

# New order
order = ExFixsense.Message.Builder.new("D")  # NewOrderSingle
|> ExFixsense.Message.Builder.set_field("11", "ORDER-#{:os.system_time()}")  # ClOrdID
|> ExFixsense.Message.Builder.set_field("55", "BTC-USD")  # Symbol
|> ExFixsense.Message.Builder.set_field("54", "1")  # Side (Buy)
|> ExFixsense.Message.Builder.set_field("38", "0.5")  # Quantity
|> ExFixsense.Message.Builder.set_field("40", "2")  # OrdType (Limit)
|> ExFixsense.Message.Builder.set_field("44", "50000.00")  # Price

ExFixsense.send_message(:my_session, order)
```

**Repeating groups** (same tag multiple times):
```elixir
message = ExFixsense.Message.Builder.new("V")
|> ExFixsense.Message.Builder.set_field("267", "2")  # NoMDEntryTypes
|> ExFixsense.Message.Builder.set_field("269", "0")  # Bid
|> ExFixsense.Message.Builder.set_field("269", "1")  # Offer

# Results in: %{"269" => ["0", "1"]}
```

---

## Authentication Strategies

### OnBehalfOf Strategy

```elixir
config :ex_fixsense, :sessions,
  my_broker: [
    host: "fix.broker.com",
    port: 9000,
    sender_comp_id: "YOUR_SENDER_COMP_ID",
    sender_sub_id: "YOUR_SENDER_SUB_ID",
    target_comp_id: "BROKER",

    logon_strategy: ExFixsense.Logon.OnBehalfOf,
    logon_fields: %{
      on_behalf_of_comp_id: "YOUR_COUNTERPARTY_ID",
      on_behalf_of_sub_id: "YOUR_USER_ID"
    },

    ssl_opts: [
      certfile: "path/to/client.crt",
      keyfile: "path/to/client.key",
      cacertfile: "path/to/ca.crt",
      verify: :verify_peer
    ]
  ]
```

**Note**: For OnBehalfOf, you must **manually add** Tag 115/116 to application messages:

```elixir
# Get OnBehalfOf credentials from config
on_behalf_of_comp_id = config.logon_fields.on_behalf_of_comp_id
on_behalf_of_sub_id = config.logon_fields.on_behalf_of_sub_id

# Add to EVERY application message
message = ExFixsense.Message.Builder.new("V")
|> ExFixsense.Message.Builder.set_field("115", on_behalf_of_comp_id)  # OnBehalfOfCompID
|> ExFixsense.Message.Builder.set_field("116", on_behalf_of_sub_id)   # OnBehalfOfSubID
|> ExFixsense.Message.Builder.set_field("262", "MD-#{:os.system_time()}")
# ... other fields
```

### Username/Password (Coinbase, Binance)

```elixir
config :ex_fixsense, :sessions,
  coinbase: [
    host: "fix.coinbase.com",
    port: 4198,
    sender_comp_id: System.get_env("COINBASE_API_KEY"),
    target_comp_id: "Coinbase",

    logon_strategy: ExFixsense.Logon.UsernamePassword,
    logon_fields: %{
      username: System.get_env("COINBASE_USERNAME"),
      password: System.get_env("COINBASE_PASSWORD")
    },

    ssl_opts: [verify: :verify_peer]
  ]
```

### Standard (Generic)

```elixir
config :ex_fixsense, :sessions,
  generic: [
    host: "fix.broker.com",
    port: 9000,
    sender_comp_id: "YOUR_ID",
    target_comp_id: "BROKER",
    logon_strategy: ExFixsense.Logon.Standard,
    ssl_opts: [verify: :verify_none]  # Use verify_peer in production!
  ]
```

---

## Running Multiple Sessions

Connect to multiple brokers simultaneously:

```elixir
# Configure multiple sessions
config :ex_fixsense, :sessions,
  broker_a: [...],
  broker_b: [...],
  broker_c: [...]

# Start all sessions
children = [
  {ExFixsense.Core.Session, session_key: :broker_a, handler: MyApp.Handler},
  {ExFixsense.Core.Session, session_key: :broker_b, handler: MyApp.Handler},
  {ExFixsense.Core.Session, session_key: :broker_c, handler: MyApp.Handler}
]

Supervisor.start_link(children, strategy: :one_for_one)

# Your handler receives session_key to identify which broker
def on_app_message(session_key, msg, _config) do
  case session_key do
    :broker_a -> handle_broker_a(msg)
    :broker_b -> handle_broker_b(msg)
    :broker_c -> handle_broker_c(msg)
  end
end
```

---

## Testing

```bash
mix test         # Run all tests
mix test --cover # Run with coverage
```

**Current status**: 119 tests, 0 failures ✅

---

## API Reference

### Main Functions

- `ExFixsense.start_session/2,3` - Start FIX session
- `ExFixsense.send_message/2` - Send FIX message
- `ExFixsense.stop_session/1` - Stop session gracefully

### Logon Strategies

- `ExFixsense.Logon.Standard` - Minimal authentication
- `ExFixsense.Logon.UsernamePassword` - Tag 553/554
- `ExFixsense.Logon.OnBehalfOf` - Tag 115/116

### Message Builder

- `Builder.new/1` - Create message
- `Builder.set_field/3` - Add field
- `Builder.get_field/2` - Get field value
- `Builder.has_field?/2` - Check field exists

### Parser

- `Parser.validate_and_parse/1` - Parse FIX message → %InMessage{}
- `Parser.fields_to_map/1` - Convert fields list → map

---

## FIX Message Type Reference

Common message types:

### Session Messages
- `A` = Logon
- `5` = Logout
- `0` = Heartbeat
- `1` = TestRequest
- `2` = ResendRequest
- `3` = Reject
- `4` = SequenceReset

### Application Messages
- `D` = NewOrderSingle
- `8` = ExecutionReport
- `9` = OrderCancelReject
- `V` = MarketDataRequest
- `W` = MarketDataSnapshotFullRefresh
- `X` = MarketDataIncrementalRefresh
- `Y` = MarketDataRequestReject
- `x` = SecurityListRequest
- `y` = SecurityList
- `AN` = PositionMaintenanceRequest
- `AP` = PositionReport
- `AO` = PositionReportAck

---

## Troubleshooting

### Connection Refused
- Check host/port in config
- Verify network connectivity
- Check broker server is running

### SSL Certificate Errors
- Verify certificate paths
- Check certificates not expired
- Use `verify: :verify_none` for testing (NOT production!)

### Logon Rejected
- Verify SenderCompID and TargetCompID
- Check credentials
- Ensure logon_strategy matches broker requirements

### Logs Not Showing

If you don't see any FIX logs in your console:

1. **Check Logger level** - Must be `:debug` or `:info` to see connection/request logs
   ```elixir
   # config/dev.exs
   config :logger, level: :debug
   ```

2. **Test Logger works**
   ```elixir
   iex> require Logger
   iex> Logger.debug("Test debug")
   iex> Logger.info("Test info")
   iex> Logger.warn("Test warn")
   iex> Logger.error("Test error")
   ```
   If you see these messages, Logger is working. If not, check your logger backends.

3. **Filter logs by session in terminal**
   ```bash
   # Filter by session key prefix
   tail -f log/dev.log | grep "\[cumberland"

   # Or watch in real-time
   iex -S mix | grep -i "FIX"
   ```

4. **Change level at runtime**
   ```elixir
   iex> Logger.configure(level: :debug)  # Show all logs
   iex> Logger.configure(level: :info)   # Hide debug, show info/warn/error
   ```

**Common issue**: Logger level set to `:warning` only shows warnings and errors, hiding `:info` and `:debug` logs.

### ResendRequest Received
If you receive ResendRequest (35=2), you must respond with:
- **GapFill** (recommended if MessageStore not implemented)
- **Resend messages** (requires MessageStore)

Example GapFill:
```elixir
gap_fill = ExFixsense.Message.Builder.new("4")
|> ExFixsense.Message.Builder.set_field("123", "Y")  # GapFillFlag
|> ExFixsense.Message.Builder.set_field("36", end_seqnum)  # NewSeqNo
ExFixsense.send_message(session_key, gap_fill)
```

---

## Production Considerations

### Error Handling

Prevent handler errors from crashing session by wrapping **both** callbacks in try/rescue:

```elixir
def on_session_message(session_key, msg, _config) do
  try do
    handle_session_message(session_key, msg)
  rescue
    e ->
      Logger.error("[#{session_key}] Session message handler error for #{msg.msg_type}: #{Exception.message(e)}")
      Logger.debug("[#{session_key}] Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      :ok  # Don't crash session
  end
end

def on_app_message(session_key, msg, _config) do
  try do
    handle_app_message(session_key, msg)
  rescue
    e ->
      Logger.error("[#{session_key}] Handler error for #{msg.msg_type}: #{Exception.message(e)}")
      Logger.debug("[#{session_key}] Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      :ok  # Don't crash session
  end
end

defp handle_session_message(session_key, msg) do
  # Your session message logic (ResendRequest, Reject, etc.)
end

defp handle_app_message(session_key, msg) do
  # Your application message routing logic
end
```

**Important**: Protect both `on_session_message` and `on_app_message` to ensure session stability.

### State Management

Handlers are **stateless callbacks**. For persistent state, use:
- **Agent** - Simple key-value store
- **GenServer** - Complex state management
- **ETS** - High-performance shared state

See `examples/USAGE_EXAMPLE.md` for patterns.

### Monitoring

Check session health:

```elixir
case Registry.lookup(ExFixsense.SessionRegistry, :my_session) do
  [{pid, _}] when is_pid(pid) -> Process.alive?(pid)
  _ -> false
end
```

### Logging

Configure Logger to see FIX session events:

#### Development
```elixir
# config/dev.exs
config :logger,
  level: :debug  # Show all FIX logs

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  level: :debug
```

#### Production
```elixir
# config/prod.exs
config :logger,
  level: :warning  # Only warnings and errors
```

#### Log Levels Used by ExFixsense Handlers
- `Logger.info` - Connection events (on_logon)
- `Logger.warn` - ResendRequest, disconnections
- `Logger.error` - Reject messages, handler errors
- `Logger.debug` - Request messages, unhandled messages, stacktraces

**Tip**: Include `[session_key]` prefix in all logs for easy filtering:
```elixir
Logger.info("[#{session_key}] Connected to #{config.host}:#{config.port}")
Logger.error("[#{session_key}] Handler error for #{msg.msg_type}: #{Exception.message(e)}")
```

**Runtime log level change**:
```elixir
iex> Logger.configure(level: :debug)  # Show everything
iex> Logger.configure(level: :info)   # Hide debug logs
```

---

## License

MIT License - see [LICENSE](LICENSE)

## Support

- **Documentation**: [hexdocs.pm/ex_fixsense](https://hexdocs.pm/ex_fixsense)
- **FIX Specification**: [fixtrading.org](https://www.fixtrading.org/standards/)
- **GitHub**: [github.com/liharsw/ex_fixsense](https://github.com/liharsw/ex_fixsense)

---

**Built with ❤️ using Elixir and OTP**
