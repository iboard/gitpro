defmodule Gitpro.Views.AboutTest do
  use ExUnit.Case, async: true

  alias Atui.Rect
  alias Gitpro.Views.About

  describe "links/0" do
    test "github and hex, each an absolute https URL" do
      links = About.links()
      labels = Enum.map(links, &elem(&1, 0))

      assert "GitHub" in labels
      assert "Hex" in labels
      assert Enum.all?(links, fn {_label, url} -> String.starts_with?(url, "https://") end)
    end

    test "they point at this package, not at a placeholder" do
      urls = Map.new(About.links())

      assert urls["GitHub"] == "https://github.com/iboard/gitpro"
      assert urls["Hex"] == "https://hex.pm/packages/gitpro"
      assert urls["Docs"] == "https://hexdocs.pm/gitpro"
    end
  end

  describe "the link cursor" do
    test "moves with every key that moves anything else, and stops at the ends" do
      {:ok, state} = About.mount([])
      assert state.cursor == 0

      for key <- [:down, {:char, "j"}, {[:ctrl], "n"}] do
        {:ok, moved} = About.handle_key(key, state)
        assert moved.cursor == 1
      end

      {:ok, state} = About.handle_key(:up, state)
      assert state.cursor == 0

      state =
        Enum.reduce(1..10, state, fn _, acc ->
          {:ok, acc} = About.handle_key({:char, "j"}, acc)
          acc
        end)

      assert state.cursor == length(About.links()) - 1
    end
  end

  describe "closing" do
    test "ESC, q and ^A all close it" do
      {:ok, state} = About.mount([])

      for key <- [:esc, {:char, "q"}, {[:ctrl], "a"}] do
        assert {:pop, _state} = About.handle_key(key, state)
      end
    end

    test "a key it has no use for does nothing" do
      {:ok, state} = About.mount([])

      assert {:ok, ^state} = About.handle_key({:char, "z"}, state)
    end
  end

  describe "place/2" do
    test "centres itself and never spills out of the terminal" do
      {:ok, state} = About.mount([])

      for {w, h} <- [{120, 40}, {80, 24}, {40, 10}, {10, 4}] do
        rect = About.place(state, Rect.sized(w, h))

        assert rect.x >= 0 and rect.y >= 0
        assert rect.x + rect.width <= w
        assert rect.y + rect.height <= h
      end
    end
  end

  describe "footnote_lines/0" do
    test "names both licences, because they are not the same one" do
      text = Enum.join(About.footnote_lines(), " ")

      assert text =~ "GPL-3.0-or-later"
      assert text =~ "Apache-2.0"
      assert text =~ "Atui"
    end
  end
end
