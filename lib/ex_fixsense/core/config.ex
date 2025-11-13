defmodule ExFixsense.Core.Config do
  @moduledoc """
  Configuration loader and validator for FIX sessions.

  Loads session configurations from application config and normalizes them
  for use by the session GenServer.

  ## Configuration Format

  Sessions are configured in `config/config.exs`:

      config :ex_fixsense, :sessions,
        cumberland_oe: [
          host: "fix-cumberlandmining.internal",
          port: 24001,
          protocol_version: "FIX.4.4",
          transport: ExFixsense.Transport.SSL,

          sender_comp_id: "c76d28d1-85d0-4991-96c8-25b8b408250a",
          sender_sub_id: "tennet-oe-01",
          target_comp_id: "cumberland",

          logon_strategy: ExFixsense.Logon.OnBehalfOf,
          logon_fields: %{
            on_behalf_of_comp_id: "a9def498-5bf7-422f-975b-9c67f444930c",
            on_behalf_of_sub_id: "tennet_cce"
          },

          ssl_opts: [
            certfile: "certs/client.crt",
            keyfile: "certs/client.key",
            cacertfile: "certs/ca.crt"
          ]
        ]

  ## Usage

      # Get a session config
      {:ok, config} = ExFixsense.Core.Config.get(:cumberland_oe)

      # Config is normalized to a map with atom keys
      config.host        # => "fix-cumberlandmining.internal"
      config.port        # => 24001
      config.logon_strategy  # => ExFixsense.Logon.OnBehalfOf

  ## Required Fields

  Every session must have:
  - `:host` - FIX server hostname
  - `:port` - FIX server port
  - `:sender_comp_id` - Your firm's ID
  - `:target_comp_id` - Broker's ID

  ## Optional Fields

  - `:sender_sub_id` - Session identifier
  - `:protocol_version` - FIX version (defaults to "FIX.4.4")
  - `:transport` - Transport module (defaults to ExFixsense.Transport.SSL)
  - `:logon_strategy` - Logon strategy module (defaults to ExFixsense.Logon.Standard)
  - `:logon_fields` - Fields required by logon strategy
  - `:ssl_opts` - SSL options (for SSL transport)
  - `:tcp_opts` - TCP options (for TCP transport)
  """

  require Logger

  @type session_config :: %{
          host: String.t(),
          port: integer(),
          sender_comp_id: String.t(),
          target_comp_id: String.t(),
          sender_sub_id: String.t() | nil,
          protocol_version: String.t(),
          transport: module(),
          logon_strategy: module(),
          logon_fields: map(),
          ssl_opts: keyword(),
          tcp_opts: keyword()
        }

  @doc """
  Get a session configuration by key.

  ## Parameters

  - `session_key` - The session key from config.exs (atom)

  ## Returns

  - `{:ok, config}` - Normalized configuration map
  - `{:error, :session_not_found}` - Session key not found in config

  ## Examples

      iex> ExFixsense.Core.Config.get(:cumberland_oe)
      {:ok, %{host: "fix.broker.com", port: 24001, ...}}

      iex> ExFixsense.Core.Config.get(:invalid_key)
      {:error, :session_not_found}
  """
  @spec get(atom()) :: {:ok, session_config()} | {:error, :session_not_found}
  def get(session_key) when is_atom(session_key) do
    case Application.get_env(:ex_fixsense, :sessions, []) do
      sessions when is_list(sessions) ->
        case Keyword.get(sessions, session_key) do
          nil ->
            Logger.warning("Session config not found: #{session_key}", [])
            {:error, :session_not_found}

          config when is_list(config) ->
            {:ok, normalize_config(config)}

          config when is_map(config) ->
            {:ok, normalize_config(config)}
        end

      _ ->
        Logger.warning("Invalid sessions config format", [])
        {:error, :session_not_found}
    end
  end

  @doc """
  Get a session configuration by key, raising if not found.

  ## Parameters

  - `session_key` - The session key from config.exs (atom)

  ## Returns

  Normalized configuration map.

  ## Raises

  `RuntimeError` if session not found.

  ## Examples

      iex> ExFixsense.Core.Config.get!(:cumberland_oe)
      %{host: "fix.broker.com", port: 24001, ...}

      iex> ExFixsense.Core.Config.get!(:invalid_key)
      ** (RuntimeError) Session config not found: invalid_key
  """
  @spec get!(atom()) :: session_config()
  def get!(session_key) when is_atom(session_key) do
    case get(session_key) do
      {:ok, config} ->
        config

      {:error, :session_not_found} ->
        raise "Session config not found: #{session_key}"
    end
  end

  @doc """
  List all configured session keys.

  ## Returns

  List of session keys (atoms).

  ## Examples

      iex> ExFixsense.Core.Config.list_sessions()
      [:cumberland_oe, :cumberland_md, :coinbase]
  """
  @spec list_sessions() :: [atom()]
  def list_sessions do
    Application.get_env(:ex_fixsense, :sessions, [])
    |> Keyword.keys()
  end

  # Private functions

  defp normalize_config(config) when is_list(config) do
    config
    |> Map.new()
    |> normalize_config()
  end

  defp normalize_config(config) when is_map(config) do
    config
    |> ensure_atom_keys()
    |> set_defaults()
    |> validate_required_fields!()
  end

  defp ensure_atom_keys(config) do
    config
    |> Enum.map(fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} when is_atom(key) -> {key, value}
    end)
    |> Map.new()
  rescue
    ArgumentError ->
      # If string key doesn't exist as atom, just convert
      config
      |> Enum.map(fn
        {key, value} when is_binary(key) -> {String.to_atom(key), value}
        {key, value} -> {key, value}
      end)
      |> Map.new()
  end

  defp set_defaults(config) do
    config
    |> Map.put_new(:protocol_version, "FIX.4.4")
    |> Map.put_new(:transport, ExFixsense.Transport.SSL)
    |> Map.put_new(:logon_strategy, ExFixsense.Logon.Standard)
    |> Map.put_new(:logon_fields, %{})
    |> Map.put_new(:ssl_opts, [])
    |> Map.put_new(:tcp_opts, [])
  end

  defp validate_required_fields!(config) do
    required = [:host, :port, :sender_comp_id, :target_comp_id]

    missing =
      Enum.filter(required, fn field ->
        not Map.has_key?(config, field) or is_nil(Map.get(config, field))
      end)

    if missing != [] do
      raise ArgumentError,
            "Missing required config fields: #{Enum.join(missing, ", ")}"
    end

    # Validate types
    unless is_binary(config.host), do: raise(ArgumentError, "host must be a string")
    unless is_integer(config.port), do: raise(ArgumentError, "port must be an integer")

    unless is_binary(config.sender_comp_id),
      do: raise(ArgumentError, "sender_comp_id must be a string")

    unless is_binary(config.target_comp_id),
      do: raise(ArgumentError, "target_comp_id must be a string")

    config
  end
end
