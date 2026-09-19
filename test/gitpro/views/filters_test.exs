defmodule Gitpro.Views.FiltersTest do
  use ExUnit.Case, async: true

  alias Atui.Rect
  alias Gitpro.Filter
  alias Gitpro.Views.Filters

  defp board_filter, do: Filter.new(["Backlog", "Ready", "Done"])

  defp loaded do
    board_filter()
    |> Filter.put_options(:state, [:open, :closed])
    |> Filter.put_options(:label, ["bug"])
    |> Filter.put_options(:assignee, ["ann"])
  end

  describe "flags/1" do
    test "every axis in turn, each in the order it lists its switches" do
      assert Filters.flags(loaded()) == [
               {:state, :open},
               {:state, :closed},
               {:column, "Backlog"},
               {:column, "Ready"},
               {:column, "Done"},
               {:column, :none},
               {:label, "bug"},
               {:label, :none},
               {:assignee, "ann"},
               {:assignee, :none}
             ]
    end
  end

  describe "rows/1" do
    test "a header per group, and the switches numbered straight through them" do
      rows = Filters.rows(loaded())

      headers = for {:header, text} <- rows, do: text
      assert headers == ["State", "Columns", "Labels", "Assignees"]

      indexes = for {:flag, _flag, index} <- rows, do: index
      assert indexes == Enum.to_list(0..9)
    end

    test "an axis with nothing on it is left out rather than given an empty heading" do
      headers = for {:header, text} <- Filters.rows(board_filter()), do: text

      assert headers == ["Columns"]
    end

    test "a board with no columns says so rather than showing a lone bucket" do
      rows = Filters.rows(Filter.new([]))

      assert {:header, "(this board has no columns)"} in rows
    end
  end

  describe "place/2" do
    test "centres itself, and shrinks to a viewport too small to hold it" do
      {:ok, state} = Filters.mount(filter: loaded())

      big = Filters.place(state, Rect.sized(100, 40))
      assert big.height == length(Filters.rows(loaded())) + 4
      assert big.x > 0

      small = Filters.place(state, Rect.sized(20, 6))
      assert small.width == 20
      assert small.height == 6
    end
  end

  describe "the cursor when the switches change underneath it" do
    test "stays on the switch it was on as the cards add groups" do
      {:ok, state} = Filters.mount(filter: board_filter())
      # The third switch of a board-only filter is the Done column.
      state = %{state | cursor: 2}
      assert Enum.at(Filters.flags(state.filter), state.cursor) == {:column, "Done"}

      {:ok, state} = Filters.handle_event({:filter, loaded()}, state)

      # Two state switches now come first, so the row number moved but the
      # switch under the cursor did not.
      assert state.cursor == 4
      assert Enum.at(Filters.flags(state.filter), state.cursor) == {:column, "Done"}
    end
  end
end
