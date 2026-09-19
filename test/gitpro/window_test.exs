defmodule Gitpro.WindowTest do
  use ExUnit.Case, async: true

  alias Gitpro.Window

  test "a list that fits starts at the top" do
    assert Window.offset(0, 4, 10) == 0
    assert Window.offset(3, 4, 10) == 0
  end

  test "the selection is pinned at the top until there is room to centre it" do
    assert Window.offset(0, 100, 10) == 0
    assert Window.offset(4, 100, 10) == 0
    assert Window.offset(5, 100, 10) == 1
  end

  test "it is centred in the middle of a long list" do
    assert Window.offset(50, 100, 10) == 46
  end

  test "and pinned at the end, so the last row is reachable" do
    assert Window.offset(99, 100, 10) == 90
    assert Window.offset(99, 100, 10) + 10 == 100
  end

  test "a box with no room in it starts at the top" do
    assert Window.offset(5, 100, 0) == 0
    assert Window.offset(5, 100, -1) == 0
  end
end
