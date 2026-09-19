defmodule Gitpro.Views.Filters do
  @moduledoc """
  The switches, as a popup: one group per axis of `Gitpro.Filter`.

  State, the board's columns, the labels the cards wear and the people they are
  assigned to — each with a switch, and each starting on, which is the only
  default that is not a guess about what someone came to look at.

      ↑ ↓ ^P ^N   move          SPACE ⏎   toggle
      a           all on        n         all off
      ESC q ^F    close

  The groups combine: a card is shown when it passes *every* axis. Within the
  multi-valued ones — labels, assignees — it passes when any of its own is on,
  which is what makes turning one label off mean "hide the cards that are only
  that" rather than "hide everything wearing it". `Gitpro.Filter` has the whole
  of that rule.

  ## Live, not on close

  Each toggle is sent straight to `Gitpro.Views.Issues` with
  `Atui.Runtime.send_event_to/3`, so the list narrows behind the popup as the
  switches are set. The popup holds the filter while it is up and the list view
  holds it the rest of the time; there is one filter, and the popup is a way of
  editing it rather than a second copy of it.

  Labels and assignees are only known once the cards have loaded, so a popup
  opened while the board is still loading has two groups in it and four a moment
  later — which is why the cursor is kept on the switch it was on rather than on
  the row number it was at.
  """

  use Atui.View

  import Atui.View, only: [assign: 3]

  alias Atui.{Runtime, Style, Text}
  alias Gitpro.{Filter, Window}
  alias Gitpro.Views.Issues

  @border Style.new(fg: :bright_cyan)
  @title Style.new(fg: :bright_cyan, bold: true)
  @header Style.new(fg: :bright_black)
  @on Style.new(fg: :bright_green)
  @off Style.new(fg: :bright_black)
  @label Style.new(fg: :white)
  @selected Style.new(fg: :bright_white, bold: true)
  @cursor Style.new(fg: :bright_cyan, bold: true)
  @help Style.new(fg: :bright_black)

  @width 42
  @max_height 26

  @impl true
  def mount(opts) do
    {:ok, %{filter: Keyword.fetch!(opts, :filter), cursor: 0}}
  end

  @doc """
  The switches, in the order the popup lists them.

  Delegated to `Gitpro.Filter.flags/1`, because the order the switches are drawn
  in and the order they are filtered in are the same order, and keeping two
  lists of that would be one too many.
  """
  @spec flags(Filter.t()) :: [Filter.flag()]
  def flags(%Filter{} = filter), do: Filter.flags(filter)

  @doc """
  The rows drawn, group headers included; only the switches can hold the cursor.

  An axis with nothing on it is left out rather than given an empty heading —
  a board with no labels on any card has no labels to switch.
  """
  @spec rows(Filter.t()) :: [{:header, String.t()} | {:flag, Filter.flag(), non_neg_integer()}]
  def rows(%Filter{} = filter) do
    {rows, _index} =
      Enum.flat_map_reduce(Filter.axes(), 0, fn axis, index ->
        case Filter.options(filter, axis) do
          [] ->
            {[], index}

          [:none] when axis == :column ->
            {[{:header, "(this board has no columns)"}], index}

          options ->
            group =
              options
              |> Enum.with_index(index)
              |> Enum.map(fn {key, i} -> {:flag, {axis, key}, i} end)

            {[{:header, Filter.axis_title(axis)} | group], index + length(options)}
        end
      end)

    rows
  end

  @impl true
  def place(state, viewport) do
    height = min(length(rows(state.filter)) + 4, @max_height)

    Rect.centered(viewport, @width, min(height, viewport.height))
  end

  @impl true
  def handle_key(key, state) when key in [:esc, {[:ctrl], "f"}, {:char, "q"}] do
    {:pop, state}
  end

  def handle_key(key, state) when key in [:up, {[:ctrl], "p"}], do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in [:down, {[:ctrl], "n"}], do: {:ok, move(state, 1)}
  def handle_key(:page_up, state), do: {:ok, move(state, -10)}
  def handle_key(:page_down, state), do: {:ok, move(state, 10)}

  def handle_key(key, state) when key in [:enter, {:char, " "}] do
    case current(state) do
      nil -> {:ok, state}
      flag -> {:ok, put_filter(state, Filter.toggle(state.filter, flag))}
    end
  end

  def handle_key({:char, "a"}, state) do
    {:ok, put_filter(state, Filter.set_all(state.filter, true))}
  end

  def handle_key({:char, "n"}, state) do
    {:ok, put_filter(state, Filter.set_all(state.filter, false))}
  end

  # A popup is modal: a key it has no use for does nothing, rather than reaching
  # the search field behind it.
  def handle_key(_key, state), do: {:ok, state}

  # The list view learns it has the keyboard back however the popup went away,
  # which is why this is announced here and not at the ESC that caused it.
  @impl true
  def unmount(_state) do
    Runtime.send_event_to(self(), Issues, :popup_closed)

    :ok
  end

  # The cards can land while the popup is open, which is what grows the label
  # and assignee groups; the cursor stays on the switch it was on.
  @impl true
  def handle_event({:filter, filter}, state) do
    flag = current(state)

    {:ok,
     state
     |> assign(:filter, filter)
     |> assign(:cursor, Enum.find_index(flags(filter), &(&1 == flag)) || state.cursor)}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def render(state, rect) do
    body = Rect.inset(rect, 1)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: " filter ", chars: :round, style: @border, title_style: @title)
    |> lines(state, body)
    |> Screen.put_text_centered(body, body.y + body.height - 1, help(body.width), @help)
  end

  # The popup is as tall as its switches until the terminal is shorter than they
  # are, and then it scrolls: a switch you cannot reach is a filter you cannot
  # turn off again.
  defp lines(screen, state, body) do
    rows = rows(state.filter)
    height = max(0, body.height - 1)
    top = Window.offset(row_of_cursor(rows, state.cursor), length(rows), height)

    rows
    |> Enum.slice(top, height)
    |> Enum.with_index(body.y)
    |> Enum.reduce(screen, fn {row, y}, acc -> line(acc, row, state, body, y) end)
  end

  # Headers take a row of their own, so where the cursor is among the switches
  # is not where it is on the screen.
  defp row_of_cursor(rows, cursor) do
    Enum.find_index(rows, &match?({:flag, _flag, ^cursor}, &1)) || 0
  end

  defp line(screen, {:header, text}, _state, body, y) do
    Screen.put_text(screen, body.x, y, Screen.truncate(text, body.width), @header)
  end

  defp line(screen, {:flag, {axis, key} = flag, index}, state, body, y) do
    on? = Filter.on?(state.filter, flag)
    selected? = index == state.cursor

    screen
    |> Screen.put_text(body.x, y, if(selected?, do: "▌", else: " "), @cursor)
    |> Screen.put_text(
      body.x + 2,
      y,
      if(on?, do: "[x]", else: "[ ]"),
      if(on?, do: @on, else: @off)
    )
    |> Screen.put_text(
      body.x + 6,
      y,
      Screen.truncate(Filter.label(axis, key), max(0, body.width - 6)),
      if(selected?, do: @selected, else: @label)
    )
  end

  defp help(width) do
    Text.first_fitting(
      ["SPACE toggle  a all  n none  ESC close", "SPACE  a  n  ESC", "ESC"],
      width
    )
  end

  defp current(state), do: state.filter |> flags() |> Enum.at(state.cursor)

  defp move(state, by) do
    last = length(flags(state.filter)) - 1

    assign(state, :cursor, state.cursor |> Kernel.+(by) |> max(0) |> min(max(0, last)))
  end

  defp put_filter(state, filter) do
    Runtime.send_event_to(self(), Issues, {:filter, filter})

    assign(state, :filter, filter)
  end
end
