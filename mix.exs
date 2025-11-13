defmodule ExFixsense.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_fixsense,
      version: "1.0.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "ExFixsense",
      source_url: "https://github.com/liharsw/ex_fixsense",
      homepage_url: "https://github.com/liharsw/ex_fixsense",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md"
        ],
        groups_for_modules: [
          Core: [
            ExFixsense,
            ExFixsense.Core.Session,
            ExFixsense.Core.Config,
            ExFixsense.SessionRegistry
          ],
          Handlers: [
            ExFixsense.SessionHandler
          ],
          Messages: [
            ExFixsense.Message.Builder,
            ExFixsense.Message.OutMessage
          ],
          "Logon Strategies": [
            ExFixsense.Logon.Behaviour,
            ExFixsense.Logon.Standard,
            ExFixsense.Logon.UsernamePassword,
            ExFixsense.Logon.OnBehalfOf
          ]
        ]
      ],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :ssl, :crypto, :inets],
      mod: {ExFixsense.Application, []}
    ]
  end

  defp description do
    """
    A broker-agnostic FIX 4.4 protocol library for Elixir with pluggable authentication,
    handler-based architecture, and production-ready features. Works with any FIX 4.4 broker.
    Includes persistent sessions, automatic reconnection, and heartbeat monitoring.
    """
  end

  defp package do
    [
      name: "ex_fixsense",
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/liharsw/ex_fixsense",
        "Documentation" => "https://hexdocs.pm/ex_fixsense",
        "Changelog" => "https://github.com/liharsw/ex_fixsense/blob/main/CHANGELOG.md"
      },
      maintainers: ["Lihar Sendhi Wijaya <liharsw@gmail.com>"]
    ]
  end

  defp deps do
    [
      # Only what we need for Phase 1: Basic OTP application
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
