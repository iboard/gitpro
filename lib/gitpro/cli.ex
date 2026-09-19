defmodule Gitpro.CLI do
  @moduledoc """
  Everything that has to work before the screen is taken over.

  `gitpro` is an escript, so this module's `main/1` is the binary. It does three
  things and then gets out of the way: reads the arguments, works out which
  board to open, and starts `Atui.Runtime` on `Gitpro.Views.Issues`.

  ## Why the board is resolved out here

  Because failing in a terminal is nicer than failing in a UI. "Not a git
  repository", "gh is not installed", "this repository is not on a project
  board" are all things to say on stdout with a non-zero exit status, not things
  to draw in a box on an alternate screen the person then has to press a key to
  leave. Both calls it takes are quick — one `git`, one small GraphQL query.

  Everything *slow* is left to the UI: the cards are fetched by the view, after
  the first frame is on screen.

  ## Usage

      gitpro                     the board of the repository you are standing in
      gitpro --project 13        that board, when the repository is on several
      gitpro --repo owner/name   somewhere other than here
      gitpro --list              the boards this repository is on, and stop
  """

  alias Gitpro.{Git, Github}
  alias Gitpro.Views.Issues

  @switches [project: :integer, repo: :string, list: :boolean, help: :boolean, version: :boolean]
  @aliases [p: :project, r: :repo, l: :list, h: :help, v: :version]

  @doc "The escript entry point."
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    case OptionParser.parse(argv, strict: @switches, aliases: @aliases) do
      {options, [], []} -> run(options)
      {_options, _rest, invalid} -> die(usage_error(invalid))
    end
  end

  defp run(options) do
    cond do
      options[:help] -> IO.puts(usage())
      options[:version] -> IO.puts("gitpro #{Gitpro.version()}")
      options[:list] -> list_projects(options)
      true -> open(options)
    end
  end

  defp open(options) do
    with {:ok, repo} <- repo(options),
         {:ok, project} <- project(repo, options[:project]),
         {:ok, board} <- Github.board(project.id) do
      start(repo, board)
    else
      {:error, message} -> die(message)
    end
  end

  defp list_projects(options) do
    with {:ok, repo} <- repo(options),
         {:ok, projects} <- Github.projects(repo) do
      IO.puts("#{repo.owner}/#{repo.name}")

      case projects do
        [] -> IO.puts("  (no project boards)")
        projects -> Enum.each(projects, &IO.puts("  " <> project_line(&1)))
      end
    else
      {:error, message} -> die(message)
    end
  end

  defp project_line(project) do
    state = if project.closed, do: "closed", else: "open"

    "##{project.number}  #{project.title}  (#{state})"
  end

  @doc """
  The repository to look at: `--repo owner/name`, or the working directory.

  The working directory is the point of the tool, so the switch exists mostly
  for looking at a board from somewhere that is not its checkout.
  """
  @spec repo(keyword()) :: {:ok, Git.repo()} | {:error, String.t()}
  def repo(options) do
    case options[:repo] do
      nil ->
        Git.repo(File.cwd!())

      "" ->
        {:error, "--repo wants an owner/name"}

      value ->
        case String.split(value, "/", trim: true) do
          [owner, name] -> {:ok, %{owner: owner, name: name}}
          _ -> {:error, "--repo wants an owner/name, not #{inspect(value)}"}
        end
    end
  end

  @doc """
  Picks the board.

  With a number, that board or nothing. Without one, the repository's first open
  board — `Gitpro.Github.projects/1` sorts open ones first — and a message
  listing the candidates when there is more than one, because silently choosing
  between two boards is the kind of thing that gets noticed an hour later.
  """
  @spec project(Git.repo(), pos_integer() | nil) ::
          {:ok, Github.project()} | {:error, String.t()}
  def project(repo, number) do
    with {:ok, projects} <- Github.projects(repo) do
      choose(repo, projects, number)
    end
  end

  defp choose(repo, [], _number) do
    {:error,
     "#{repo.owner}/#{repo.name} is not on a project board — " <>
       "link one from the repository's Projects tab, then run gitpro again"}
  end

  defp choose(repo, projects, nil) do
    case Enum.reject(projects, & &1.closed) do
      [] -> {:ok, hd(projects)}
      [only] -> {:ok, only}
      [first | _] = open -> {:ok, first} |> tap(fn _ -> note_choice(repo, open) end)
    end
  end

  defp choose(repo, projects, number) do
    case Enum.find(projects, &(&1.number == number)) do
      nil ->
        {:error,
         "#{repo.owner}/#{repo.name} has no project ##{number}. " <>
           "Try: " <> Enum.map_join(projects, ", ", &"##{&1.number} #{&1.title}")}

      project ->
        {:ok, project}
    end
  end

  # Printed before the alternate screen opens, so it is still on the terminal
  # after the UI exits.
  defp note_choice(_repo, [chosen | _] = projects) do
    others = Enum.reject(projects, &(&1.number == chosen.number))

    IO.puts(
      :stderr,
      "gitpro: opening ##{chosen.number} #{chosen.title}; " <>
        "also on " <>
        Enum.map_join(others, ", ", &"##{&1.number} #{&1.title}") <>
        " (--project to choose)"
    )
  end

  # halt: :system is the default, and what an escript wants: when the UI quits,
  # the VM goes with it and the shell gets its prompt back.
  defp start(repo, board) do
    {:ok, pid} =
      Atui.Runtime.start_link(view: Issues, view_opts: [repo: repo, board: board])

    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end

  defp usage_error(invalid) do
    "unknown option " <>
      Enum.map_join(invalid, ", ", fn {switch, _value} -> switch end) <>
      "\n\n" <> usage()
  end

  defp usage do
    """
    gitpro #{Gitpro.version()} — browse a GitHub project board from the terminal

    USAGE
      gitpro [options]

    OPTIONS
      -p, --project NUMBER   the board to open, when the repository is on several
      -r, --repo OWNER/NAME  a repository other than the working directory's
      -l, --list             list the boards this repository is on, and stop
      -h, --help             this
      -v, --version          the version

    KEYS
      type                   search, as you type
      ^I                     the selected card in full (^I is what TAB sends)
      ^O, ENTER              open the selected card in a browser
      ^F                     the filter switches: state, columns, labels,
                             assignees
      up down ^P ^N          move the selection
      PgUp PgDn              a screen at a time
      ^R                     reload the board
      ESC                    clear the search, then quit

    IN A POPUP
      ESC, q                 close it
      up down j k            in the card popup, the next or previous card
      PgUp PgDn ^U ^D        in the card popup, scroll the description
      SPACE, a, n            in the filter popup, toggle / all on / all off
    """
  end

  defp die(message) do
    IO.puts(:stderr, "gitpro: " <> message)
    System.halt(1)
  end
end
