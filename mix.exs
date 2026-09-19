defmodule Gitpro.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/iboard/gitpro"

  def project do
    [
      app: :gitpro,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "gitpro",
      source_url: @source_url
    ]
  end

  # No application callback module: the UI is started by Gitpro.CLI once it
  # knows which project it is looking at, not by the application starting.
  def application do
    [extra_applications: [:logger]]
  end

  # A single self-contained file, which is the whole point: `gitpro` is meant
  # to be run from whatever repository you happen to be standing in.
  #
  #   +Bc  Ctrl-C arrives as a byte the runtime can act on, instead of opening
  #        the emulator BREAK menu over the UI.
  #
  # Shipping this in the package is what makes `mix escript.install hex gitpro`
  # build the same binary on someone else's machine.
  defp escript do
    [
      main_module: Gitpro.CLI,
      name: "gitpro",
      emu_args: "+Bc"
    ]
  end

  defp description do
    "Browse a GitHub project board from the terminal: search as you type, " <>
      "filter by state, kanban column, label and assignee, and read a card " <>
      "without leaving the shell."
  end

  # An application rather than a library — what Hex buys is
  # `mix escript.install hex gitpro`, so the escript config and the sources it
  # needs are what goes in. The tests and the dev launcher stay behind.
  defp package do
    [
      licenses: ["GPL-3.0-or-later"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      groups_for_modules: [
        "Starting up": [Gitpro, Gitpro.CLI],
        "What to show": [Gitpro.Filter, Gitpro.Item],
        "Where it comes from": [Gitpro.Git, Gitpro.Github],
        Screens: [Gitpro.Views.Issues, Gitpro.Views.Detail, Gitpro.Views.Filters],
        Odds: [Gitpro.Browser, Gitpro.Window]
      ]
    ]
  end

  # The UI toolkit, from Hex rather than from the checkout beside this one, so
  # that cloning this repository is enough to build it. To work on both at once,
  # point it back at the path:
  #
  #     {:atui, path: "../atui"}
  defp deps do
    [
      {:atui, "~> 0.3.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
