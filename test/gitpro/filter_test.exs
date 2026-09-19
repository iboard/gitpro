defmodule Gitpro.FilterTest do
  use ExUnit.Case, async: true

  alias Gitpro.{Filter, Item}

  defp item(attrs) do
    Item.index(
      struct!(
        %Item{id: "i1", kind: :issue, number: 1, title: "a card", state: :open, repo: "acme/web"},
        attrs
      )
    )
  end

  defp board do
    [
      item(
        id: "1",
        number: 1,
        title: "Fix the login form",
        state: :open,
        column: "Ready",
        labels: ["bug"],
        assignees: ["ann"]
      ),
      item(
        id: "2",
        number: 2,
        title: "Login rate limit",
        state: :closed,
        column: "Done",
        labels: ["bug", "security"],
        assignees: ["ben"]
      ),
      item(id: "3", number: 3, title: "Docs for the API", state: :open, column: nil),
      item(
        id: "4",
        number: 4,
        title: "Bump deps",
        state: :merged,
        kind: :pull_request,
        column: "Done",
        labels: ["chore"]
      ),
      item(id: "5", number: nil, title: "Think about caching", kind: :draft, state: :none)
    ]
  end

  defp loaded do
    Filter.new(["Backlog", "Ready", "Done"])
    |> Filter.put_options(:state, [:open, :closed, :merged, :draft])
    |> Filter.put_options(:label, ["bug", "chore", "security"])
    |> Filter.put_options(:assignee, ["ann", "ben"])
  end

  defp ids(items), do: Enum.map(items, & &1.id)

  describe "new/1" do
    test "every switch starts on, with the board's columns in the board's order" do
      filter = Filter.new(["Backlog", "Ready", "Done"])

      assert Filter.options(filter, :column) == ["Backlog", "Ready", "Done", :none]
      assert Enum.all?(Filter.flags(filter), &Filter.on?(filter, &1))
      refute Filter.narrowed?(filter)
    end

    test "the axes the cards decide start empty, so they hide nothing" do
      filter = Filter.new(["Ready"])

      assert Filter.options(filter, :state) == []
      assert Filter.options(filter, :label) == []
      assert ids(Filter.apply(filter, board())) == ~w(1 2 3 4 5)
    end

    test "a board with no columns still has the no-column bucket" do
      assert Filter.options(Filter.new([]), :column) == [:none]
    end
  end

  describe "put_options/3" do
    test "the empty bucket is added for the axes where it means something" do
      filter = loaded()

      assert List.last(Filter.options(filter, :label)) == :none
      assert List.last(Filter.options(filter, :assignee)) == :none
      assert List.last(Filter.options(filter, :column)) == :none
      refute :none in Filter.options(filter, :state)
    end

    test "switches already set survive new options arriving" do
      filter =
        Filter.new(["Ready"])
        |> Filter.toggle({:column, "Ready"})
        |> Filter.put_options(:label, ["bug"])

      refute Filter.on?(filter, {:column, "Ready"})
      assert Filter.on?(filter, {:label, "bug"})
    end

    test "a switch nobody has touched is on, whether it is known about or not" do
      filter = Filter.new([])

      assert Filter.on?(filter, {:label, "a-label-that-arrived-later"})
    end
  end

  describe "apply/2 across the axes" do
    test "hides nothing while every switch is on" do
      assert ids(Filter.apply(loaded(), board())) == ~w(1 2 3 4 5)
    end

    test "a merged pull request is its own state, not a closed one" do
      closed = loaded() |> Filter.toggle({:state, :closed})
      assert ids(Filter.apply(closed, board())) == ~w(1 3 4 5)

      merged = loaded() |> Filter.toggle({:state, :merged})
      assert ids(Filter.apply(merged, board())) == ~w(1 2 3 5)
    end

    test "a draft is its own state too" do
      filter = loaded() |> Filter.toggle({:state, :draft})

      assert ids(Filter.apply(filter, board())) == ~w(1 2 3 4)
    end

    test "a column switch removes that column's cards" do
      filter = loaded() |> Filter.toggle({:column, "Done"})

      assert ids(Filter.apply(filter, board())) == ~w(1 3 5)
    end

    test "cards with no column have a switch of their own" do
      filter = loaded() |> Filter.toggle({:column, :none})

      assert ids(Filter.apply(filter, board())) == ~w(1 2 4)
    end

    test "the axes combine: a card has to pass every one of them" do
      filter =
        loaded()
        |> Filter.toggle({:state, :closed})
        |> Filter.toggle({:column, :none})
        |> Filter.toggle({:state, :draft})

      assert ids(Filter.apply(filter, board())) == ~w(1 4)
    end
  end

  describe "apply/2 with the labels" do
    test "a card passes when any label it wears is on" do
      # Card 2 wears bug and security; turning bug off leaves security on.
      filter = loaded() |> Filter.toggle({:label, "bug"})

      assert ids(Filter.apply(filter, board())) == ~w(2 3 4 5)
    end

    test "turning off every label a card wears hides it" do
      filter = loaded() |> Filter.toggle({:label, "bug"}) |> Filter.toggle({:label, "security"})

      assert ids(Filter.apply(filter, board())) == ~w(3 4 5)
    end

    test "unlabelled cards are a switch of their own" do
      filter = loaded() |> Filter.toggle({:label, :none})

      assert ids(Filter.apply(filter, board())) == ~w(1 2 4)
    end

    test "one label on its own shows the cards wearing it, and nothing else" do
      filter =
        Enum.reduce(["bug", "security", :none], loaded(), &Filter.toggle(&2, {:label, &1}))

      assert ids(Filter.apply(filter, board())) == ~w(4)
    end
  end

  describe "apply/2 with the assignees" do
    test "an assignee switch hides that person's cards" do
      filter = loaded() |> Filter.toggle({:assignee, "ann"})

      assert ids(Filter.apply(filter, board())) == ~w(2 3 4 5)
    end

    test "unassigned is a switch of its own" do
      filter = loaded() |> Filter.toggle({:assignee, :none})

      assert ids(Filter.apply(filter, board())) == ~w(1 2)
    end

    test "a card assigned to two people passes while either is on" do
      pair = [item(id: "p", assignees: ["ann", "ben"])]
      filter = loaded() |> Filter.toggle({:assignee, "ann"})

      assert ids(Filter.apply(filter, pair)) == ~w(p)

      both = filter |> Filter.toggle({:assignee, "ben"})
      assert Filter.apply(both, pair) == []
    end
  end

  describe "set_all/2" do
    test "turns everything off, and back on, leaving the query alone" do
      filter = loaded() |> Filter.put_query("login")

      off = Filter.set_all(filter, false)
      assert Filter.apply(off, board()) == []
      assert off.query == "login"

      on = Filter.set_all(off, true)
      assert ids(Filter.apply(on, board())) == ~w(1 2)
    end

    test "it can only turn off the switches it knows about" do
      off = Filter.new([]) |> Filter.set_all(false)

      # A label that arrives afterwards was never switched off, so it is on.
      assert Filter.on?(off, {:label, "arrived-later"})
    end
  end

  describe "apply/2 with the query" do
    test "matches the title, whatever the case" do
      filter = Filter.new([]) |> Filter.put_query("LOGIN")

      assert ids(Filter.apply(filter, board())) == ~w(1 2)
    end

    test "every term has to match, so another word only narrows" do
      filter = Filter.new([]) |> Filter.put_query("login rate")

      assert ids(Filter.apply(filter, board())) == ~w(2)
    end

    test "order of the terms makes no difference" do
      one = Filter.new([]) |> Filter.put_query("rate login")
      other = Filter.new([]) |> Filter.put_query("login rate")

      assert Filter.apply(one, board()) == Filter.apply(other, board())
    end

    test "the number, the column, the labels and the assignees are searchable" do
      items = [item(id: "x", number: 42, labels: ["bug"], assignees: ["iboard"], column: "Ready")]

      for query <- ["#42", "bug", "iboard", "ready", "acme/web"] do
        assert ids(Filter.apply(Filter.put_query(Filter.new([]), query), items)) == ~w(x),
               "#{query} did not match"
      end
    end

    test "the body is not searchable — that would be a different tool" do
      items = [item(id: "x", title: "Nothing", body: "a long description mentioning widgets")]

      assert Filter.apply(Filter.put_query(Filter.new([]), "widgets"), items) == []
    end

    test "whitespace alone is not a filter" do
      filter = Filter.new([]) |> Filter.put_query("   ")

      assert length(Filter.apply(filter, board())) == 5
      refute Filter.narrowed?(filter)
    end

    test "filtering only takes rows away — it never reorders them" do
      filter = loaded() |> Filter.put_query("e")
      result = Filter.apply(filter, board())

      assert ids(result) == board() |> Enum.filter(&(&1 in result)) |> ids()
    end
  end

  describe "summary/1" do
    test "says nothing while every switch is on" do
      assert Filter.summary(loaded()) == nil
    end

    test "names the states that are left" do
      filter = loaded() |> Filter.toggle({:state, :closed}) |> Filter.toggle({:state, :merged})

      # Two on and two off: a tie prints the ones that are on.
      assert Filter.summary(filter) == "open,draft"
    end

    test "lists the columns that are on while they are the shorter list" do
      filter =
        loaded()
        |> Filter.toggle({:column, "Backlog"})
        |> Filter.toggle({:column, "Done"})
        |> Filter.toggle({:column, :none})

      assert Filter.summary(filter) == "Ready"
    end

    test "names what is off instead when that is shorter" do
      filter = loaded() |> Filter.toggle({:column, "Done"})

      assert Filter.summary(filter) == "-Done"
    end

    test "each axis says its piece, and the empty bucket is named for its axis" do
      filter = loaded() |> Filter.toggle({:label, :none}) |> Filter.toggle({:assignee, "ann"})

      assert Filter.summary(filter) == "-Unlabelled -ann"
    end

    test "says so when a whole axis is off" do
      filter = loaded() |> Filter.set_all(false)

      assert Filter.summary(filter) == "no state no column no label no assignee"
    end
  end

  describe "label/2" do
    test "the empty bucket is named for the axis it belongs to" do
      assert Filter.label(:column, :none) == "No column"
      assert Filter.label(:label, :none) == "Unlabelled"
      assert Filter.label(:assignee, :none) == "Unassigned"
    end

    test "everything else is written as it is" do
      assert Filter.label(:state, :open) == "open"
      assert Filter.label(:label, "bug") == "bug"
    end
  end
end
