defmodule Gitpro.Views.Detail do
  @moduledoc """
  One card, in full: its title, what is known about it, and its description.

  Opened with `^I` over the list and centred on the terminal. Everything in it
  was fetched with the board, so it opens instantly and keeps working with the
  network gone — including the card it moves to next.

      ↑ ↓ j k ^P ^N     the next or previous card    ⏎ ^O    open in a browser
      PgUp PgDn ^D ^U   scroll a long description    ESC q   close
      Home              back to the top

  ## Moving without closing

  `j` and `k` walk the list with the popup still open, which is what reading
  through a column is: open the first card, keep pressing `j`. The popup does
  not hold the list — it asks `Gitpro.Views.Issues` to move its selection and is
  handed back whatever is now selected. So the selection behind the popup moves
  with it, the search and the switches still decide what "next" means, and
  closing the popup leaves the cursor on the card you stopped at rather than the
  one you started from.

  ## Drawing someone else's text

  An issue body is text from the internet being drawn into a terminal in raw
  mode, which is the one place where that is dangerous: an escape sequence in it
  would move the cursor, repaint colours the view never asked for, or set the
  window title. `Atui.Text.sanitize/1` takes those out, and `Atui.Text.wrap/2`
  breaks what is left to the popup's width. Markdown is left as it was written —
  a terminal that renders it is a different program, and the source of a list is
  still a readable list.

  ## Lines, then a window onto them

  `lines/2` turns the card into the rows to draw, and the view keeps a scroll
  offset into that list. It is a pure function of the card and a width, so what
  a long body looks like at forty columns is a test rather than a screenshot.
  """

  use Atui.View

  import Atui.View, only: [assign: 3]

  alias Atui.{Fetch, Style, Text}
  alias Gitpro.{Browser, Item}

  @border Style.new(fg: :bright_magenta)
  @title_style Style.new(fg: :bright_magenta, bold: true)
  @heading Style.new(fg: :bright_white, bold: true)
  @field Style.new(fg: :bright_black)
  @value Style.new(fg: :white)
  @label_style Style.new(fg: :bright_yellow)
  @body Style.new(fg: :white)
  @url Style.new(fg: :bright_blue)
  @rule Style.new(fg: :bright_black)
  @help Style.new(fg: :bright_black)
  @notice Style.new(fg: :bright_green)
  @error Style.new(fg: :bright_red, bold: true)

  @open Style.new(fg: :bright_green)
  @closed Style.new(fg: :bright_magenta)
  @draft Style.new(fg: :bright_black)

  # Up and down move between cards rather than through one, because a list you
  # walk is what the popup is opened in the middle of; the body scrolls a screen
  # at a time instead.
  @previous [:up, {:char, "k"}, {[:ctrl], "p"}]
  @next [:down, {:char, "j"}, {[:ctrl], "n"}]

  @max_width 84
  @max_height 30
  @notice_ms 2_500

  @impl true
  def mount(opts) do
    {:ok, %{item: Keyword.fetch!(opts, :item), scroll: 0, notice: nil, error: nil}}
  end

  @impl true
  def place(_state, viewport) do
    Rect.centered(
      viewport,
      min(@max_width, max(0, viewport.width - 4)),
      min(@max_height, max(0, viewport.height - 2))
    )
  end

  # ^I is the byte Tab sends, so the key that opened this closes it again.
  @impl true
  def handle_key(key, state) when key in [:esc, :tab, {:char, "q"}], do: {:pop, state}

  def handle_key(key, state) when key in @previous, do: {:ok, walk(state, -1)}
  def handle_key(key, state) when key in @next, do: {:ok, walk(state, 1)}

  def handle_key(key, state) when key in [:page_up, {[:ctrl], "u"}], do: {:ok, scroll(state, -10)}

  def handle_key(key, state) when key in [:page_down, {[:ctrl], "d"}],
    do: {:ok, scroll(state, 10)}

  def handle_key(:home, state), do: {:ok, assign(state, :scroll, 0)}

  def handle_key(key, state) when key in [:enter, {[:ctrl], "o"}], do: {:ok, open(state)}

  # A popup is modal: a key it has no use for is a key that does nothing, not
  # one that reaches the search field behind it.
  def handle_key(_key, state), do: {:ok, state}

  @impl true
  def handle_event({:open, :ok}, state), do: {:ok, notice(state, "opened in your browser")}

  def handle_event({:open, {:error, message}}, state) do
    {:ok, assign(state, :error, message)}
  end

  # The answer to a walk: whatever Gitpro.Views.Issues has selected now. A card
  # that did not change — the ends of the list — still arrives, and redrawing
  # the same card is the honest way to show there is nothing past it.
  def handle_event({:item, %Item{} = item}, state) do
    {:ok, state |> assign(:item, item) |> assign(:scroll, 0) |> assign(:notice, nil)}
  end

  def handle_event(:clear_notice, state) do
    {:ok, state |> assign(:notice, nil) |> assign(:error, nil)}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def unmount(_state) do
    Atui.Runtime.send_event_to(self(), Gitpro.Views.Issues, :popup_closed)

    :ok
  end

  @impl true
  def render(state, rect) do
    body = Rect.inset(rect, 1)
    lines = lines(state.item, body.width)
    height = max(0, body.height - 1)
    top = state.scroll |> min(max(0, length(lines) - height)) |> max(0)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect,
      title: title(state.item),
      chars: :round,
      style: @border,
      title_style: @title_style
    )
    |> draw(lines, body, top, height)
    |> Screen.put_text_centered(
      body,
      body.y + body.height - 1,
      footer(state, lines, top, height, body.width),
      footer_style(state)
    )
  end

  @doc """
  The card as the rows to draw, each with the style to draw it in.

  The metadata comes first and only for the fields the card actually has — an
  empty "Milestone:" is a row that says nothing — then a rule, then the body.
  """
  @spec lines(Item.t(), integer()) :: [{String.t(), Style.t() | nil}]
  def lines(%Item{} = item, width) when width > 0 do
    heading(item, width) ++ [{"", nil}] ++ fields(item, width) ++ body_lines(item, width)
  end

  def lines(%Item{}, _width), do: []

  defp heading(item, width) do
    item.title
    |> fit(width)
    |> Enum.map(&{&1, @heading})
  end

  # Word wrap first, because that is what reads; then break whatever is still
  # too long, which is a URL or a path — the things with no spaces in them, and
  # the things worth having in full rather than elided.
  defp fit(text, width) when width > 0 do
    text
    |> Text.sanitize()
    |> Text.wrap(width)
    |> Enum.flat_map(&Text.hard_wrap(&1, width))
  end

  defp fit(_text, _width), do: []

  defp fields(item, width) do
    [
      {"State", state_text(item), state_style(item)},
      {"Column", item.column, @value},
      {"Repo", item.repo, @value},
      {"Author", item.author && "@" <> item.author, @value},
      {"Labels", present(item.labels), @label_style},
      {"Assignees", present(Enum.map(item.assignees, &("@" <> &1))), @value},
      {"Milestone", item.milestone, @value},
      {"Created", date(item.created_at), @value},
      {"Updated", date(item.updated_at), @value},
      {"URL", item.url, @url}
    ]
    |> Enum.reject(fn {_name, value, _style} -> value in [nil, ""] end)
    |> Enum.flat_map(&field_rows(&1, width))
  end

  # A value too long for the row is wrapped under its own label rather than
  # elided: a URL you cannot read is a URL you cannot type out again. The row
  # carries the value's style; the label is muted afterwards, when it is drawn.
  defp field_rows({name, value, style}, width) do
    label = String.pad_trailing(name <> ":", 11)
    indent = String.duplicate(" ", 11)

    case fit(value, max(1, width - 11)) do
      [] -> []
      [first | rest] -> [{label <> first, style} | Enum.map(rest, &{indent <> &1, style})]
    end
  end

  defp body_lines(%Item{body: body}, width) when is_binary(body) do
    case String.trim(body) do
      "" ->
        []

      body ->
        rows =
          body
          |> Text.sanitize()
          |> String.split("\n")
          |> Enum.flat_map(fn
            "" -> [""]
            line -> fit(line, width)
          end)
          |> Enum.map(&{&1, @body})

        [{"", nil}, {String.duplicate("─", width), @rule}, {"", nil}] ++ rows
    end
  end

  defp body_lines(%Item{}, _width), do: []

  defp present([]), do: nil
  defp present(values), do: Enum.join(values, ", ")

  # The timestamp is ISO 8601 and the time of day is never what anyone is
  # asking; the date is.
  defp date(nil), do: nil
  defp date(timestamp), do: timestamp |> String.slice(0, 10)

  defp state_text(item) do
    case Item.state_key(item) do
      :draft -> "draft"
      key -> Atom.to_string(key)
    end
  end

  defp state_style(item) do
    case Item.state_key(item) do
      :open -> @open
      :draft -> @draft
      _ -> @closed
    end
  end

  @doc "The popup's own title: the card's number, or what it is instead."
  @spec title(Item.t()) :: String.t()
  def title(%Item{number: nil}), do: " draft "
  def title(%Item{number: number}), do: " ##{number} "

  defp draw(screen, lines, body, top, height) do
    lines
    |> Enum.slice(top, height)
    |> Enum.with_index(body.y)
    |> Enum.reduce(screen, fn {{text, style}, y}, acc ->
      acc
      |> Screen.put_text(body.x, y, Screen.truncate(text, body.width), style)
      |> mute_label(text, body, y)
    end)
  end

  # Only a metadata row has a label, and a label is exactly the run up to and
  # including its colon in the first eleven columns.
  defp mute_label(screen, text, body, y) do
    case :binary.match(text, ":") do
      {index, _length} when index < 10 ->
        Screen.restyle(screen, Rect.new(body.x, y, index + 1, 1), @field)

      _ ->
        screen
    end
  end

  defp footer(%{error: error}, _lines, _top, _height, width) when is_binary(error) do
    Screen.truncate("! " <> error, width)
  end

  defp footer(%{notice: notice}, _lines, _top, _height, width) when is_binary(notice) do
    Screen.truncate("✓ " <> notice, width)
  end

  defp footer(_state, lines, top, height, width) do
    scroll = if length(lines) > top + height, do: "PgDn scroll   ", else: ""

    [
      "↑↓ jk next/prev   " <> scroll <> "⏎ open in browser   ESC close",
      "↑↓ jk next/prev   " <> scroll <> "⏎ open   ESC close",
      "jk next/prev   ⏎ open   ESC close",
      "jk  ⏎  ESC",
      "ESC"
    ]
    |> Text.first_fitting(width)
  end

  defp footer_style(%{error: error}) when is_binary(error), do: @error
  defp footer_style(%{notice: notice}) when is_binary(notice), do: @notice
  defp footer_style(_state), do: @help

  defp scroll(state, by), do: assign(state, :scroll, max(0, state.scroll + by))

  # The list owns the selection, so moving is a question asked of it rather than
  # an index kept here — two copies of "which card" is how they come to disagree.
  defp walk(state, by) do
    Atui.Runtime.send_event_to(self(), Gitpro.Views.Issues, {:move, by})

    state
  end

  defp open(%{item: %Item{url: url}} = state) when is_binary(url) do
    Fetch.start(__MODULE__, :open, fn -> Browser.open(url) end)

    state
  end

  defp open(state), do: notice(state, "a draft card has nothing to open")

  defp notice(state, message) do
    Atui.Runtime.schedule_event_to(__MODULE__, :clear_notice, @notice_ms)

    state |> assign(:notice, message) |> assign(:error, nil)
  end
end
