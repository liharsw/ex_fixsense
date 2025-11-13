defmodule ExFixsense.SessionRegistry do
  @moduledoc """
  Registry for named FIX sessions.

  This allows sessions to be looked up by atom keys like `:cumberland_md`
  instead of PIDs.

  ## Usage

  The registry is started automatically by the application supervisor.
  You don't need to start it manually.

  Sessions register themselves when they start:

      {:ok, pid} = ExFixsense.Core.Session.start_link(
        session_key: :cumberland_md,
        handler: MyApp.MarketDataHandler
      )

      # Session is now registered as :cumberland_md

  You can look up sessions by key:

      case Registry.lookup(ExFixsense.SessionRegistry, :cumberland_md) do
        [{pid, _}] -> # Session found
        [] -> # Session not running
      end

  ## Architecture

  This is a standard Elixir Registry with `:unique` keys.
  Each session key can only be registered once.

  If you try to start a second session with the same key,
  it will fail with `{:error, {:already_started, pid}}`.
  """

  @doc """
  Child spec for starting the registry under a supervisor.

  This is used by the application supervisor.
  """
  def child_spec(_opts) do
    Registry.child_spec(
      keys: :unique,
      name: __MODULE__
    )
  end
end
