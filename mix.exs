defmodule Gitpro.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :gitpro,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      name: "gitpro"
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
  defp escript do
    [
      main_module: Gitpro.CLI,
      name: "gitpro",
      emu_args: "+Bc"
    ]
  end

  # The UI toolkit, from Hex rather than from the checkout beside this one, so
  # that cloning this repository is enough to build it. To work on both at once,
  # point it at the path again:
  #
  #     {:atui, path: "../atui"}
  defp deps do
    [
      {:atui, "~> 0.3.0"}
    ]
  end
end
