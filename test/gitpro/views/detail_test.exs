defmodule Gitpro.Views.DetailTest do
  use ExUnit.Case, async: true

  alias Atui.Rect
  alias Gitpro.Item
  alias Gitpro.Views.Detail

  defp card(attrs \\ []) do
    Item.index(
      struct!(
        %Item{
          id: "1",
          kind: :issue,
          number: 42,
          title: "Fix the login form",
          state: :open,
          url: "https://github.com/acme/web/issues/42",
          repo: "acme/web",
          column: "Ready",
          author: "ann",
          labels: ["bug", "ux"],
          assignees: ["ben"],
          milestone: "v2",
          created_at: "2026-09-01T10:00:00Z",
          updated_at: "2026-09-12T08:30:00Z",
          body: "The form loses focus on submit."
        },
        attrs
      )
    )
  end

  defp texts(item, width), do: item |> Detail.lines(width) |> Enum.map(&elem(&1, 0))

  describe "lines/2" do
    test "the title comes first, then the metadata, then the body" do
      lines = texts(card(), 60)

      assert hd(lines) == "Fix the login form"
      assert "State:     open" in lines
      assert "Column:    Ready" in lines
      assert "Repo:      acme/web" in lines
      assert "Author:    @ann" in lines
      assert "Labels:    bug, ux" in lines
      assert "Assignees: @ben" in lines
      assert "Milestone: v2" in lines
      assert "URL:       https://github.com/acme/web/issues/42" in lines
      assert "The form loses focus on submit." in lines
    end

    test "a timestamp is shown as the date, which is the part anyone reads" do
      lines = texts(card(), 60)

      assert "Created:   2026-09-01" in lines
      assert "Updated:   2026-09-12" in lines
    end

    test "a field the card does not have gets no row of its own" do
      lines = texts(card(milestone: nil, assignees: [], labels: []), 60)

      refute Enum.any?(lines, &String.starts_with?(&1, "Milestone:"))
      refute Enum.any?(lines, &String.starts_with?(&1, "Assignees:"))
      refute Enum.any?(lines, &String.starts_with?(&1, "Labels:"))
      assert "State:     open" in lines
    end

    test "a merged pull request and a draft say what they are" do
      assert "State:     merged" in texts(card(kind: :pull_request, state: :merged), 60)
      assert "State:     draft" in texts(card(kind: :draft, state: :none, number: nil), 60)
    end

    test "a long title is wrapped rather than cut" do
      title = String.duplicate("word ", 40) |> String.trim()
      lines = texts(card(title: title), 40)

      wrapped = Enum.take_while(lines, &(&1 != ""))
      assert length(wrapped) > 1
      assert Enum.all?(wrapped, &(String.length(&1) <= 40))
      assert wrapped |> Enum.join(" ") == title
    end

    test "a value too long for its row wraps under its own label" do
      lines = texts(card(url: "https://github.com/acme/" <> String.duplicate("x", 60)), 40)

      [first | rest] = Enum.filter(lines, &(&1 =~ "github.com" or &1 =~ "xxx"))
      assert String.starts_with?(first, "URL:       ")
      assert Enum.all?(rest, &String.starts_with?(&1, "           "))
    end

    test "the body keeps its own line breaks, and its blank lines" do
      lines = texts(card(body: "first\n\nsecond"), 60)

      assert "first" in lines
      assert "second" in lines

      assert Enum.find_index(lines, &(&1 == "first")) + 2 ==
               Enum.find_index(lines, &(&1 == "second"))
    end

    test "a card with no body stops after the metadata" do
      lines = texts(card(body: nil), 60)
      assert List.last(lines) =~ "github.com"

      assert texts(card(body: "   "), 60) == lines
    end

    test "every line fits the width it was given" do
      item = card(body: String.duplicate("a long sentence that has to be wrapped ", 10))

      for width <- [80, 60, 40, 20, 12] do
        assert Enum.all?(texts(item, width), &(String.length(&1) <= width)),
               "a line spilled at #{width} columns"
      end
    end

    test "an escape sequence in someone else's text never reaches the terminal" do
      item = card(title: "\e[31mred\e[0m", body: "\e]0;title\a and \e[2J")
      lines = texts(item, 60)

      refute Enum.any?(lines, &String.contains?(&1, "\e"))
      assert Enum.any?(lines, &String.contains?(&1, "red"))
    end

    test "a width with no room in it draws nothing rather than raising" do
      assert Detail.lines(card(), 0) == []
    end
  end

  describe "title/1" do
    test "the card's number, or what it is instead" do
      assert Detail.title(card()) == " #42 "
      assert Detail.title(card(number: nil)) == " draft "
    end
  end

  describe "place/2" do
    test "centres itself and never spills out of the terminal" do
      {:ok, state} = Detail.mount(item: card())

      for {w, h} <- [{120, 40}, {80, 24}, {40, 10}, {10, 4}] do
        rect = Detail.place(state, Rect.sized(w, h))

        assert rect.x >= 0 and rect.y >= 0
        assert rect.x + rect.width <= w
        assert rect.y + rect.height <= h
      end
    end
  end

  describe "scrolling" do
    test "a screen at a time, and never above the top" do
      {:ok, state} = Detail.mount(item: card())

      {:ok, state} = Detail.handle_key(:page_down, state)
      assert state.scroll == 10

      {:ok, state} = Detail.handle_key({[:ctrl], "d"}, state)
      assert state.scroll == 20

      {:ok, state} = Detail.handle_key({[:ctrl], "u"}, state)
      assert state.scroll == 10

      {:ok, state} = Detail.handle_key(:home, state)
      assert state.scroll == 0

      {:ok, state} = Detail.handle_key(:page_up, state)
      assert state.scroll == 0
    end
  end

  describe "walking the list" do
    test "the vertical keys ask the list to move rather than scrolling" do
      {:ok, state} = Detail.mount(item: card())
      {:ok, state} = Detail.handle_key(:page_down, state)

      for key <- [:down, {:char, "j"}, {[:ctrl], "n"}, :up, {:char, "k"}, {[:ctrl], "p"}] do
        assert {:ok, ^state} = Detail.handle_key(key, state)
      end

      # Nothing was scrolled by any of them.
      assert state.scroll == 10
    end

    test "the card the list hands back replaces this one, from the top" do
      {:ok, state} = Detail.mount(item: card())
      {:ok, state} = Detail.handle_key(:page_down, state)

      next = card(id: "2", number: 43, title: "Another card")
      {:ok, state} = Detail.handle_event({:item, next}, state)

      assert state.item.id == "2"
      assert state.scroll == 0
      assert Detail.title(state.item) == " #43 "
    end
  end

  describe "closing" do
    test "ESC, q and Tab all close it" do
      {:ok, state} = Detail.mount(item: card())

      for key <- [:esc, {:char, "q"}, :tab] do
        assert {:pop, _state} = Detail.handle_key(key, state)
      end
    end

    test "a key it has no use for does nothing, rather than reaching the list" do
      {:ok, state} = Detail.mount(item: card())

      assert {:ok, ^state} = Detail.handle_key({:char, "z"}, state)
    end
  end
end
