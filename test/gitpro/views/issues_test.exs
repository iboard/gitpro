defmodule Gitpro.Views.IssuesTest do
  use ExUnit.Case, async: true

  alias Atui.{Runtime, Screen}
  alias Gitpro.{Filter, Item}
  alias Gitpro.Views.{About, Detail, Filters, Issues}

  @board %{
    id: "PVT_1",
    number: 13,
    title: "e-Matrix System",
    url: "https://github.com/orgs/acme/projects/13",
    column_field: "Status",
    columns: ["Backlog", "Ready", "Done"]
  }

  @repo %{owner: "acme", name: "web"}

  defp card(attrs) do
    Item.index(
      struct!(
        %Item{
          id: "x",
          kind: :issue,
          number: 1,
          title: "card",
          state: :open,
          repo: "acme/web",
          url: "https://github.com/acme/web/issues/1"
        },
        attrs
      )
    )
  end

  defp cards do
    [
      card(
        id: "1",
        number: 11,
        title: "Fix the login form",
        column: "Ready",
        labels: ["bug"],
        assignees: ["ann"],
        body: "The form loses focus on submit.",
        author: "ann",
        created_at: "2026-09-01T10:00:00Z"
      ),
      card(
        id: "2",
        number: 12,
        title: "Login rate limit",
        state: :closed,
        column: "Done",
        labels: ["bug", "security"]
      ),
      card(id: "3", number: 13, title: "Docs for the API", column: "Backlog", assignees: ["ben"]),
      card(id: "4", number: 14, title: "Cache the dashboard", column: nil)
    ]
  end

  # The loader stands in for the GraphQL call: the view never knows the
  # difference, and the test never needs a token.
  defp start_ui(opts \\ []) do
    items = Keyword.get(opts, :items, cards())
    loader = Keyword.get(opts, :loader, fn -> {:ok, items} end)

    pid =
      start_supervised!(
        Supervisor.child_spec(
          {Runtime,
           view: Issues,
           view_opts: [repo: @repo, board: @board, loader: loader],
           headless: true,
           halt: :stop,
           name: nil,
           size: Keyword.get(opts, :size, {100, 24})},
          id: {Issues, System.unique_integer()}
        )
      )

    if Keyword.get(opts, :wait, true), do: await_load(pid), else: Runtime.screen(pid)

    pid
  end

  # The loader answers from a process of its own, so a frame drawn the instant
  # the UI starts is a frame drawn before it. Waiting for the flag to clear is
  # what makes a test about loaded cards a test about loaded cards.
  defp await_load(pid, tries \\ 200) do
    Runtime.screen(pid)

    if Runtime.view_state(pid, Issues).loading? and tries > 0 do
      Process.sleep(2)
      await_load(pid, tries - 1)
    end

    pid
  end

  # A key can set off a round trip between views — the detail popup asking the
  # list to move, the list answering with what it landed on. Each message is one
  # more turn of the runtime's loop, so a test that reads state straight after
  # the key can read it before the answer has been handled. Each screen/1 is a
  # call, and a call is only answered once everything ahead of it has been.
  defp press(pid, key) do
    Runtime.send_key(pid, key)
    settle(pid)
  end

  defp settle(pid, turns \\ 3) do
    for _ <- 1..turns, do: Runtime.screen(pid)
    pid
  end

  defp type(pid, text) do
    text |> String.graphemes() |> Enum.each(&press(pid, {:char, &1}))
    pid
  end

  defp text(pid), do: pid |> Runtime.screen() |> Screen.to_text()
  defp state(pid), do: Runtime.view_state(pid, Issues)
  defp shown(pid), do: pid |> state() |> Map.fetch!(:shown) |> Enum.map(& &1.id)
  defp selected(pid), do: pid |> state() |> Map.fetch!(:selected_id)

  describe "the list" do
    test "draws every card, with its number, column and repository" do
      frame = start_ui() |> text()

      assert frame =~ "acme/web"
      assert frame =~ "#13 e-Matrix System"
      assert frame =~ "#11"
      assert frame =~ "Fix the login form"
      assert frame =~ "Ready"
      assert frame =~ "Cache the dashboard"
    end

    test "says so while the board is still loading" do
      # A loader that never answers: the first frame is drawn without it.
      pid = start_ui(loader: fn -> Process.sleep(:infinity) end, wait: false)

      assert text(pid) =~ "loading the board"
      assert state(pid).loading?
    end

    test "a board that could not be loaded says why in the footer" do
      pid = start_ui(loader: fn -> {:error, "gh: not logged in"} end)

      assert text(pid) =~ "could not load the board"
      assert text(pid) =~ "not logged in"
      refute state(pid).loading?
    end

    test "a loader that raises is an error, not a crash" do
      pid = start_ui(loader: fn -> raise "boom" end)

      assert Process.alive?(pid)
      assert text(pid) =~ "boom"
    end

    test "an empty board says it is empty" do
      assert start_ui(items: []) |> text() =~ "this board has no cards on it"
    end

    test "the counter shows the total, and both numbers once it is narrowed" do
      pid = start_ui()
      assert text(pid) =~ "4"

      type(pid, "login")
      assert text(pid) =~ "2/4"
    end
  end

  describe "searching" do
    test "typing filters the list without a key to start it" do
      pid = start_ui() |> type("login")

      assert shown(pid) == ~w(1 2)
      assert text(pid) =~ "Fix the login form"
      refute text(pid) =~ "Docs for the API"
    end

    test "every term narrows further" do
      pid = start_ui() |> type("login rate")

      assert shown(pid) == ~w(2)
    end

    test "backspace widens it again" do
      pid = start_ui() |> type("login") |> press(:backspace) |> press(:backspace)

      # "log" also matches the Backlog column, which is the point of searching
      # the whole row rather than only the title.
      assert shown(pid) == ~w(1 2 3)
      assert state(pid).filter.query == "log"
    end

    test "nothing matching says which of the two ways emptied the list" do
      pid = start_ui() |> type("zzz")

      assert text(pid) =~ "nothing matches"
      assert text(pid) =~ "ESC clears the search"
    end

    test "ESC clears the search before it quits" do
      pid = start_ui() |> type("login") |> press(:esc)

      assert Process.alive?(pid)
      assert state(pid).filter.query == ""
      assert shown(pid) == ~w(1 2 3 4)
    end

    test "q in the list is a letter, not a way out" do
      pid = start_ui() |> type("q")

      assert Process.alive?(pid)
      assert state(pid).filter.query == "q"
    end

    test "ESC on an empty search quits" do
      pid = start_ui()
      ref = Process.monitor(pid)

      Runtime.send_key(pid, :esc)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "the selection" do
    test "starts on the first card and moves with the arrows" do
      pid = start_ui()
      assert selected(pid) == "1"

      press(pid, :down)
      assert selected(pid) == "2"

      press(pid, :up)
      assert selected(pid) == "1"
    end

    test "^N and ^P move it too, because the arrows are not always to hand" do
      pid = start_ui() |> press({[:ctrl], "n"}) |> press({[:ctrl], "n"})
      assert selected(pid) == "3"

      press(pid, {[:ctrl], "p"})
      assert selected(pid) == "2"
    end

    test "stops at either end rather than wrapping" do
      pid = start_ui() |> press(:up) |> press(:up)
      assert selected(pid) == "1"

      for _ <- 1..10, do: press(pid, :down)
      assert selected(pid) == "4"
    end

    test "follows the card it is on when the list narrows under it" do
      pid = start_ui() |> press(:down)
      assert selected(pid) == "2"

      type(pid, "login")

      assert shown(pid) == ~w(1 2)
      assert selected(pid) == "2"
      assert state(pid).cursor == 1
    end

    test "falls back to a row that exists when its card is filtered away" do
      pid = start_ui() |> press(:down) |> press(:down)
      assert selected(pid) == "3"

      type(pid, "login")

      assert selected(pid) == "2"
      assert state(pid).cursor == 1
    end

    test "an empty list leaves nothing selected" do
      pid = start_ui() |> type("zzz")

      assert shown(pid) == []
      assert selected(pid) == nil
    end
  end

  describe "the window onto a long list" do
    test "a list longer than the screen scrolls the selection into view" do
      many = for n <- 1..60, do: card(id: "#{n}", number: n, title: "card number #{n}")
      pid = start_ui(items: many, size: {80, 14})

      assert text(pid) =~ "card number 1"
      refute text(pid) =~ "card number 40"

      for _ <- 1..40, do: press(pid, :down)

      assert text(pid) =~ "card number 41"
      refute text(pid) =~ "card number 1 "
    end

    test "PgDn and PgUp move ten at a time" do
      many = for n <- 1..60, do: card(id: "#{n}", number: n)
      pid = start_ui(items: many) |> press(:page_down)

      assert state(pid).cursor == 10

      press(pid, :page_up)
      assert state(pid).cursor == 0
    end
  end

  describe "the filter popup" do
    test "^F opens it over the list, with a group per axis" do
      pid = start_ui() |> press({[:ctrl], "f"})

      assert Runtime.view_stack(pid) == [Filters, Issues]
      frame = text(pid)
      assert frame =~ "filter"
      assert frame =~ "[x] open"
      assert frame =~ "[x] Backlog"
      assert frame =~ "[x] No column"
      assert frame =~ "Labels"
      assert frame =~ "[x] bug"
      assert frame =~ "Assignees"
      assert frame =~ "[x] ann"
      assert frame =~ "[x] Unassigned"
    end

    test "only the states the board actually has get a switch" do
      frame = start_ui() |> press({[:ctrl], "f"}) |> text()

      assert frame =~ "[x] open"
      assert frame =~ "[x] closed"
      refute frame =~ "merged"
      refute frame =~ "draft"
    end

    test "a label switch hides the cards that wear only that label" do
      pid = start_ui() |> press({[:ctrl], "f"})
      # State, state, four columns, then the labels: bug is the seventh switch.
      for _ <- 1..6, do: press(pid, :down)
      press(pid, :enter)

      assert text(pid) =~ "[ ] bug"
      # Card 2 also wears security, so it stays; card 1 wears only bug.
      assert shown(pid) == ~w(2 3 4)
    end

    test "an assignee switch hides that person's cards" do
      pid = start_ui() |> press({[:ctrl], "f"})
      # ...then the two labels and the unlabelled bucket, then the assignees.
      for _ <- 1..9, do: press(pid, :down)
      press(pid, :enter)

      assert text(pid) =~ "[ ] ann"
      assert shown(pid) == ~w(2 3 4)
    end

    test "the list view claims nothing while the popup is up" do
      pid = start_ui() |> press({[:ctrl], "f"}) |> type("login")

      # "login" went to the popup, not to the search field.
      assert state(pid).filter.query == ""
      assert Runtime.view_stack(pid) == [Filters, Issues]
    end

    test "a state toggle narrows the list behind the popup, as it is made" do
      pid = start_ui() |> press({[:ctrl], "f"}) |> press(:down) |> press({:char, " "})

      assert shown(pid) == ~w(1 3 4)
      refute Filter.on?(state(pid).filter, {:state, :closed})
      assert text(pid) =~ "[ ] closed"
    end

    test "a column flag removes that column's cards" do
      pid = start_ui() |> press({[:ctrl], "f"})
      # The two state switches, then the columns in board order: Backlog,
      # Ready, and four rows down, Done.
      for _ <- 1..4, do: press(pid, :down)
      press(pid, :enter)

      assert text(pid) =~ "[ ] Done"
      assert shown(pid) == ~w(1 3 4)
    end

    test "n turns every switch off and a turns them back on" do
      pid = start_ui() |> press({[:ctrl], "f"}) |> press({:char, "n"})
      assert shown(pid) == []

      press(pid, {:char, "a"})
      assert shown(pid) == ~w(1 2 3 4)
    end

    test "ESC closes it and gives the search field the keyboard back" do
      pid = start_ui() |> press({[:ctrl], "f"}) |> press(:esc) |> type("docs")

      assert Runtime.view_stack(pid) == [Issues]
      refute state(pid).popup?
      assert shown(pid) == ~w(3)
    end

    test "q closes it too, and the search field takes its letters back" do
      pid = start_ui() |> press({[:ctrl], "f"}) |> press({:char, "q"})

      assert Runtime.view_stack(pid) == [Issues]

      type(pid, "q")
      assert state(pid).filter.query == "q"
    end

    test "the switches survive the popup being closed and opened again" do
      pid =
        start_ui() |> press({[:ctrl], "f"}) |> press(:down) |> press({:char, " "}) |> press(:esc)

      assert shown(pid) == ~w(1 3 4)

      press(pid, {[:ctrl], "f"})
      assert text(pid) =~ "[ ] closed"
    end

    test "a popup opened while the board loads grows the other groups when it lands" do
      me = self()

      # The loader waits to be let go, so the popup can be opened mid-load.
      loader = fn ->
        send(me, {:loading, self()})

        receive do
          :go -> {:ok, cards()}
        end
      end

      pid = start_ui(loader: loader, wait: false)
      assert_receive {:loading, fetch}

      press(pid, {[:ctrl], "f"})
      frame = text(pid)
      assert frame =~ "Columns"
      refute frame =~ "Labels"

      send(fetch, :go)
      await_load(pid)

      frame = text(pid)
      assert frame =~ "Labels"
      assert frame =~ "[x] bug"
      assert frame =~ "Assignees"
    end

    test "the switches and the search narrow together" do
      pid =
        start_ui()
        |> type("login")
        |> press({[:ctrl], "f"})
        |> press(:down)
        |> press({:char, " "})

      assert shown(pid) == ~w(1)
    end

    test "the footer says which switches are on once one is off" do
      pid =
        start_ui() |> press({[:ctrl], "f"}) |> press(:down) |> press({:char, " "}) |> press(:esc)

      assert text(pid) =~ "[open]"
    end
  end

  describe "the detail popup" do
    test "^I opens the selected card in full" do
      pid = start_ui() |> press({[:ctrl], "i"})

      assert Runtime.view_stack(pid) == [Detail, Issues]
      frame = text(pid)
      assert frame =~ "#11"
      assert frame =~ "Fix the login form"
      assert frame =~ "State:     open"
      assert frame =~ "Labels:    bug"
      assert frame =~ "The form loses focus on submit."
    end

    test "Tab opens it too, because ^I is the byte Tab sends" do
      pid = start_ui() |> press(:tab)

      assert Runtime.view_stack(pid) == [Detail, Issues]
    end

    test "it shows the card under the cursor, not the first one" do
      pid = start_ui() |> press(:down) |> press(:down) |> press({[:ctrl], "i"})

      assert text(pid) =~ "Docs for the API"
      assert Runtime.view_state(pid, Detail).item.id == "3"
    end

    test "it follows the search, so what is opened is what is selected" do
      pid = start_ui() |> type("docs") |> press({[:ctrl], "i"})

      assert Runtime.view_state(pid, Detail).item.id == "3"
    end

    test "^I with nothing selected does nothing at all" do
      pid = start_ui() |> type("zzz") |> press({[:ctrl], "i"})

      assert Runtime.view_stack(pid) == [Issues]
      assert Process.alive?(pid)
    end

    test "the list view claims nothing while it is up" do
      pid = start_ui() |> press({[:ctrl], "i"}) |> type("login")

      assert state(pid).filter.query == ""
      assert Runtime.view_stack(pid) == [Detail, Issues]
    end

    test "ESC closes it and gives the search field the keyboard back" do
      pid = start_ui() |> press({[:ctrl], "i"}) |> press(:esc) |> type("docs")

      assert Runtime.view_stack(pid) == [Issues]
      refute state(pid).popup?
      assert shown(pid) == ~w(3)
    end

    test "j and k walk to the next and previous card without closing it" do
      pid = start_ui() |> press({[:ctrl], "i"})
      assert Runtime.view_state(pid, Detail).item.id == "1"

      press(pid, {:char, "j"})
      assert Runtime.view_state(pid, Detail).item.id == "2"
      assert text(pid) =~ "Login rate limit"
      assert Runtime.view_stack(pid) == [Detail, Issues]

      press(pid, {:char, "k"})
      assert Runtime.view_state(pid, Detail).item.id == "1"
    end

    test "the arrows walk it too" do
      pid = start_ui() |> press({[:ctrl], "i"}) |> press(:down) |> press(:down)

      assert Runtime.view_state(pid, Detail).item.id == "3"

      press(pid, :up)
      assert Runtime.view_state(pid, Detail).item.id == "2"
    end

    test "the selection behind the popup moves with it" do
      pid = start_ui() |> press({[:ctrl], "i"}) |> press({:char, "j"}) |> press({:char, "j"})

      assert selected(pid) == "3"
      assert state(pid).cursor == 2

      # Closing leaves the cursor on the card you stopped at.
      press(pid, :esc)
      assert selected(pid) == "3"
    end

    test "walking stops at either end rather than wrapping" do
      pid = start_ui() |> press({[:ctrl], "i"})

      for _ <- 1..10, do: press(pid, {:char, "j"})
      assert Runtime.view_state(pid, Detail).item.id == "4"

      for _ <- 1..10, do: press(pid, {:char, "k"})
      assert Runtime.view_state(pid, Detail).item.id == "1"
    end

    test "the search still decides what next means" do
      pid = start_ui() |> type("login") |> press({[:ctrl], "i"})
      assert Runtime.view_state(pid, Detail).item.id == "1"

      press(pid, {:char, "j"})
      assert Runtime.view_state(pid, Detail).item.id == "2"

      # Card 3 is filtered out, so there is nothing past card 2.
      press(pid, {:char, "j"})
      assert Runtime.view_state(pid, Detail).item.id == "2"
    end

    test "q closes it, the same as ESC" do
      pid = start_ui() |> press({[:ctrl], "i"}) |> press({:char, "q"})

      assert Runtime.view_stack(pid) == [Issues]
      refute state(pid).popup?
      assert Process.alive?(pid)
    end

    test "a long body scrolls inside it" do
      long =
        card(id: "L", number: 99, title: "Long", body: Enum.map_join(1..80, "\n", &"line #{&1}"))

      pid = start_ui(items: [long]) |> press({[:ctrl], "i"})

      assert text(pid) =~ "line 1"
      refute text(pid) =~ "line 60"

      for _ <- 1..6, do: press(pid, :page_down)

      assert text(pid) =~ "line 60"

      press(pid, :home)
      assert text(pid) =~ "line 1"
    end
  end

  describe "opening in a browser" do
    test "^O on a draft says there is nothing to open, rather than nothing" do
      pid =
        start_ui(items: [card(id: "d", kind: :draft, number: nil, url: nil, title: "A thought")])

      press(pid, {[:ctrl], "o"})

      assert text(pid) =~ "nothing to open"
    end

    test "enter does the same thing, as it always did" do
      pid =
        start_ui(items: [card(id: "d", kind: :draft, number: nil, url: nil, title: "A thought")])

      press(pid, :enter)

      assert text(pid) =~ "nothing to open"
    end
  end

  describe "the about popup" do
    test "^A opens it, with the version and the links in it" do
      pid = start_ui() |> press({[:ctrl], "a"})

      assert Runtime.view_stack(pid) == [About, Issues]
      frame = text(pid)
      assert frame =~ "about"
      assert frame =~ "gitpro"
      assert frame =~ Gitpro.version()
      assert frame =~ "github.com/iboard/gitpro"
      assert frame =~ "hex.pm/packages/gitpro"
      assert frame =~ "GPL-3.0-or-later"
    end

    test "the list view claims nothing while it is up" do
      pid = start_ui() |> press({[:ctrl], "a"}) |> type("login")

      assert state(pid).filter.query == ""
      assert Runtime.view_stack(pid) == [About, Issues]
    end

    test "ESC closes it and gives the search field the keyboard back" do
      pid = start_ui() |> press({[:ctrl], "a"}) |> press(:esc) |> type("docs")

      assert Runtime.view_stack(pid) == [Issues]
      refute state(pid).popup?
      assert shown(pid) == ~w(3)
    end

    test "^A takes the search field's start-of-line, which Home still does" do
      pid = start_ui() |> type("login")
      assert Runtime.view_state(pid, Issues).input.cursor == 5

      press(pid, :home)
      assert Runtime.view_state(pid, Issues).input.cursor == 0

      # And ^A opens the popup rather than moving the cursor.
      press(pid, :end)
      press(pid, {[:ctrl], "a"})
      assert Runtime.view_stack(pid) == [About, Issues]
      assert Runtime.view_state(pid, Issues).input.cursor == 5
    end
  end

  describe "reloading" do
    test "^R asks the loader again and takes the new cards" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      loader = fn ->
        n = Agent.get_and_update(agent, &{&1, &1 + 1})
        {:ok, [card(id: "r#{n}", number: n, title: "run #{n}")]}
      end

      pid = start_ui(loader: loader)
      assert text(pid) =~ "run 0"

      pid |> press({[:ctrl], "r"}) |> await_load()
      assert text(pid) =~ "run 1"
    end

    test "the search survives a reload" do
      pid = start_ui() |> type("login") |> press({[:ctrl], "r"}) |> await_load()

      assert state(pid).filter.query == "login"
      assert shown(pid) == ~w(1 2)
    end
  end

  describe "the row" do
    test "gives the title what the fixed columns do not take" do
      assert Issues.row_widths(100) == %{title: 58, column: 14, repo: 18}
    end

    test "drops the repository, then the column, as the terminal narrows" do
      assert %{repo: 0, column: 14} = Issues.row_widths(50)
      assert %{repo: 0, column: 0, title: 20} = Issues.row_widths(30)
      assert %{title: 0, column: 0, repo: 0} = Issues.row_widths(8)
    end

    test "a draft is drawn without a number it does not have" do
      pid = start_ui(items: [card(id: "d", kind: :draft, number: nil, title: "A thought")])

      row = pid |> text() |> String.split("\r\n") |> Enum.find(&(&1 =~ "A thought"))

      assert row
      refute row =~ "#"
    end
  end

  describe "the title bar" do
    test "names the repository and the board" do
      assert Issues.title(%{repo: @repo, board: @board}, 100) =~ "acme/web"
      assert Issues.title(%{repo: @repo, board: @board}, 100) =~ "#13 e-Matrix System"
    end

    test "shortens rather than spilling out of a narrow terminal" do
      for width <- [100, 60, 30, 12, 4] do
        title = Issues.title(%{repo: @repo, board: @board}, width)

        assert String.length(title) <= max(0, width - 2), "#{width} columns: #{title}"
      end
    end
  end
end
