defmodule ExFixsense.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for named FIX sessions
      ExFixsense.SessionRegistry
    ]

    opts = [strategy: :one_for_one, name: ExFixsense.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
