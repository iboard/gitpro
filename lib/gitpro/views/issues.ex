defmodule Gitpro.Views.Issues do
  @moduledoc """
  The first and only screen: a search field, the cards under it, a footer.

  Typing filters. There is no mode to enter and no key to press first — the
  search field has the keyboard from the moment the UI opens, because searching
  is what this tool is for and anything else is a key you have to remember. So
  every printable character is the search field's, and everything the
  application does of its own is bound to a key the field does not want: the
  vertical arrows, Enter, ESC and a handful of Ctrl chords.

      ^I          the card in full          ^O ⏎   open the card in a browser
      ^F          the filter switches       ^R     reload the board
      ↑ ↓ ^P ^N   move the selection        ESC    clear the search, then quit
      PgUp PgDn   a screen at a time        ^C     quit

  `^I` is the byte the Tab key sends — a terminal cannot tell the two apart —
  so Tab opens the card too, and the switches moved to `^F` to make room.

  `q` is a letter, so here it goes into the search field like any other. In the
  popups, where there is nothing to type into, it closes — see
  `Gitpro.Views.Detail` and `Gitpro.Views.Filters`.

  ## Loading

  A board of a few hundred cards is several round trips, so the cards are
  fetched in an `Atui.Fetch` and the first frame is drawn before any of them
  have arrived. The UI is usable while it loads — the search field takes what
  you type, and the query is already applied when the cards land.

  ## Who holds the filter

  This view does. `Gitpro.Views.Filters` is pushed over it as a popup and sends
  the filter back on every toggle, so the list behind the popup narrows while
  the switches are being set rather than when the popup closes. While either
  popup is up, this view — which as the root view sees every key first — claims
  nothing, or the search field would eat the keys meant for them.

  The switches for the labels and the assignees cannot exist before the cards
  do, so `load/1` hands the filter the ones it found every time the board
  arrives. Switches already set survive that, and a popup that is open while it
  happens is told as well.
  """

  use Atui.View

  import Atui.View, only: [assign: 2, assign: 3]

  alias Atui.{Fetch, Layout, Style, Text, TextInput}
  alias Gitpro.{Browser, Filter, Github, Item, Window}
  alias Gitpro.Views.{Detail, Filters}

  @border Style.new(fg: :blue)
  @title Style.new(fg: :bright_blue, bold: true)
  @muted Style.new(fg: :bright_black)
  @rule Style.new(fg: :bright_black)
  @prompt Style.new(fg: :bright_cyan, bold: true)
  @query Style.new(fg: :bright_white)
  @placeholder Style.new(fg: :bright_black)
  @row Style.new(fg: :white)
  @selected Style.new(fg: :bright_white, bold: true)
  @selection_bar Style.new(fg: :bright_cyan, bold: true)
  @number Style.new(fg: :bright_black)
  @column Style.new(fg: :bright_yellow)
  @repo Style.new(fg: :bright_black)
  @error Style.new(fg: :bright_red, bold: true)
  @notice Style.new(fg: :bright_green)
  @footer Style.new(fg: :bright_black)
  @count Style.new(fg: :bright_cyan)

  @open Style.new(fg: :bright_green)
  @closed Style.new(fg: :bright_magenta)
  @draft Style.new(fg: :bright_black)

  # Long enough to read, short enough that it is gone before it is in the way.
  @notice_ms 2_500

  @impl true
  def mount(opts) do
    board = Keyword.fetch!(opts, :board)

    state =
      %{
        repo: Keyword.fetch!(opts, :repo),
        board: board,
        loader:
          Keyword.get(opts, :loader, fn -> Github.items(board.id, board[:column_field]) end),
        items: [],
        shown: [],
        filter: Filter.new(board.columns),
        input: TextInput.new(placeholder: "type to search"),
        cursor: 0,
        selected_id: nil,
        loading?: true,
        error: nil,
        notice: nil,
        popup?: false
      }
      |> load()

    {:ok, state}
  end

  # ## Keys

  # The popup owns the keyboard while it is up; claiming anything here would
  # take it away from the flags.
  @impl true
  def handle_key(_key, %{popup?: true} = state), do: {:pass, state}

  # ^I and Tab are the same byte, so both open the card.
  def handle_key(key, state) when key in [:tab, {[:ctrl], "i"}], do: detail(state)

  def handle_key({[:ctrl], "f"}, state) do
    {:push, Filters, [filter: state.filter], assign(state, :popup?, true)}
  end

  def handle_key(key, state) when key in [:up, {[:ctrl], "p"}], do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in [:down, {[:ctrl], "n"}], do: {:ok, move(state, 1)}
  def handle_key(:page_up, state), do: {:ok, move(state, -10)}
  def handle_key(:page_down, state), do: {:ok, move(state, 10)}

  def handle_key(key, state) when key in [:enter, {[:ctrl], "o"}] do
    {:ok, open_selected(state)}
  end

  def handle_key({[:ctrl], "r"}, state), do: {:ok, load(state)}

  def handle_key({[:ctrl], "q"}, state), do: {:halt, state}

  # ESC undoes the search before it quits: a list narrowed to nothing is the
  # moment ESC is reached for, and losing the session over it would be rude.
  def handle_key(:esc, state) do
    if TextInput.empty?(state.input) do
      {:halt, state}
    else
      {:ok, state |> assign(:input, TextInput.clear(state.input)) |> search()}
    end
  end

  def handle_key(key, state) do
    case state.input |> TextInput.handle_key(key) |> TextInput.into(state) do
      {:ok, state} -> {:ok, search(state)}
      {:pass, state} -> {:pass, state}
    end
  end

  # ## Events

  @impl true
  def handle_event({:items, {:ok, items}}, state) do
    filter = observed(state.filter, items)

    # The labels and the assignees only exist once the cards do, so a filter
    # popup that was opened while the board loaded is holding a filter with two
    # groups in it. It is told, and grows the other two where it stands.
    if state.popup?, do: Atui.Runtime.send_event_to(self(), Filters, {:filter, filter})

    {:ok,
     state
     |> assign(items: items, loading?: false, error: nil)
     |> assign(:filter, filter)
     |> refilter()}
  end

  def handle_event({:items, {:error, message}}, state) do
    {:ok, assign(state, loading?: false, error: message)}
  end

  # The popup sends its filter on every toggle, so the list narrows underneath
  # it rather than when it closes.
  def handle_event({:filter, filter}, state) do
    {:ok, state |> assign(:filter, filter) |> refilter()}
  end

  def handle_event(:popup_closed, state), do: {:ok, assign(state, :popup?, false)}

  # The detail popup walking the list: this view moves its own selection — the
  # one it has always owned — and hands back whatever that landed on. At either
  # end nothing moves and the same card goes back, which is what "there is
  # nothing past this" looks like without a second copy of the list to ask.
  def handle_event({:move, by}, state) do
    state = move(state, by)

    Atui.Runtime.send_event_to(self(), Detail, {:item, selected(state)})

    {:ok, state}
  end

  def handle_event({:open, :ok}, state), do: {:ok, notice(state, "opened in your browser")}

  def handle_event({:open, {:error, message}}, state) do
    {:ok, assign(state, :error, message)}
  end

  def handle_event(:clear_notice, state), do: {:ok, assign(state, :notice, nil)}

  def handle_event(_event, state), do: {:ok, state}

  # ## Rendering

  @impl true
  def render(state, rect) do
    body = Rect.inset(rect, 1)
    {search, rest} = Layout.split_top(body, 1)
    {rule, rest} = Layout.split_top(rest, 1)
    {list, footer} = Layout.split_bottom(rest, 1)

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect, title: title(state, rect.width), style: @border, title_style: @title)
    |> TextInput.draw(state.input, search,
      style: @query,
      prompt_style: @prompt,
      placeholder_style: @placeholder
    )
    |> Screen.put_text(rule.x, rule.y, String.duplicate("─", rule.width), @rule)
    |> list(state, list)
    |> Screen.put_text(footer.x, footer.y, footer(state, footer.width), footer_style(state))
    |> counter(state, footer)
  end

  @doc """
  The title bar: what repository this is, and which board is being shown.

  Shortens rather than spilling — the board's title is the first thing to go,
  because the repository is what tells you the tool is pointed at the right
  place.
  """
  @spec title(map(), pos_integer()) :: String.t()
  def title(state, width) do
    repo = "#{state.repo.owner}/#{state.repo.name}"
    board = "##{state.board.number} #{state.board.title}"

    Text.first_fitting(
      [
        " gitpro · #{repo} · #{board} ",
        " #{repo} · #{board} ",
        " #{repo} ",
        " gitpro ",
        ""
      ],
      max(0, width - 2)
    )
  end

  @doc """
  The footer, as much of it as fits.

  An error takes the row over when there is one: a message that does not fit is
  worse than no shortcuts, and the shortcuts are still on screen next frame.
  """
  @spec footer(map(), pos_integer()) :: String.t()
  def footer(%{error: error}, width) when is_binary(error) do
    Screen.truncate("! " <> error, width)
  end

  def footer(%{notice: notice}, width) when is_binary(notice) do
    Screen.truncate("✓ " <> notice, width)
  end

  def footer(state, width) do
    flags = Filter.summary(state.filter)

    [
      "^I details   ^O open   ^F filter   ^R reload   ESC quit" <> flag_suffix(flags),
      "^I details   ^O open   ^F filter   ESC quit" <> flag_suffix(flags),
      "^I ^O ^F   ESC quit" <> flag_suffix(flags),
      "^F filter  ESC quit",
      "ESC quit"
    ]
    |> Text.first_fitting(max(0, width - counter_width(state)))
    |> Screen.truncate(width)
  end

  defp footer_style(%{error: error}) when is_binary(error), do: @error
  defp footer_style(%{notice: notice}) when is_binary(notice), do: @notice
  defp footer_style(_state), do: @footer

  defp flag_suffix(nil), do: ""
  defp flag_suffix(flags), do: "   [#{flags}]"

  @doc """
  How the widths of a row are divided at `width` columns.

  Returns `%{title:, column:, repo:}` — the fixed parts (the marker, the state
  glyph and the number) are the same at every width, and what is left goes to
  the title. The repository is dropped first when there is not enough for
  everything, then the board column: a board is usually one repository's, and
  the column is on screen in the flags anyway.
  """
  @spec row_widths(integer()) :: %{title: integer(), column: integer(), repo: integer()}
  def row_widths(width) do
    fixed = 2 + 2 + 6

    cond do
      width >= fixed + 20 + 14 + 18 -> %{title: width - fixed - 14 - 18, column: 14, repo: 18}
      width >= fixed + 16 + 14 -> %{title: width - fixed - 14, column: 14, repo: 0}
      width > fixed -> %{title: width - fixed, column: 0, repo: 0}
      true -> %{title: 0, column: 0, repo: 0}
    end
  end

  defp list(screen, _state, rect) when rect.height <= 0, do: screen

  defp list(screen, %{loading?: true, items: []}, rect) do
    Screen.put_lines_centered(screen, rect, ["loading the board…"], @muted)
  end

  defp list(screen, %{shown: [], error: error}, rect) when is_binary(error) do
    Screen.put_lines_centered(screen, rect, ["could not load the board"], @error)
  end

  defp list(screen, %{shown: []} = state, rect) do
    Screen.put_lines_centered(screen, rect, empty_lines(state), @muted)
  end

  defp list(screen, state, rect) do
    count = length(state.shown)
    top = Window.offset(state.cursor, count, rect.height)
    widths = row_widths(rect.width)

    state.shown
    |> Enum.slice(top, rect.height)
    |> Enum.with_index(top)
    |> Enum.reduce(screen, fn {item, index}, acc ->
      row(acc, item, rect, rect.y + index - top, index == state.cursor, widths)
    end)
  end

  @doc """
  What is said where the rows would be when there are none.

  Which of the two ways of narrowing emptied the list is the one thing worth
  saying here — being told to clear a search you never typed is how a filter
  that is quietly on stays on.
  """
  @spec empty_lines(map()) :: [String.t()]
  def empty_lines(%{items: []}), do: ["this board has no cards on it"]

  def empty_lines(state) do
    query? = String.trim(state.filter.query) != ""
    flags? = Filter.flags_narrowed?(state.filter)

    case {query?, flags?} do
      {true, true} -> ["nothing matches", "ESC clears the search, ⇥ the flags"]
      {true, false} -> ["nothing matches", "ESC clears the search"]
      {false, true} -> ["every card is filtered out", "^F opens the switches"]
      {false, false} -> ["this board has no cards on it"]
    end
  end

  defp row(screen, item, rect, y, selected?, widths) do
    text = if selected?, do: @selected, else: @row
    x = rect.x

    screen
    |> Screen.put_text(x, y, if(selected?, do: "▌ ", else: "  "), @selection_bar)
    |> Screen.put_text(x + 2, y, glyph(item), glyph_style(item))
    |> Screen.put_text(x + 4, y, number(item), @number)
    |> Screen.put_text(x + 10, y, pad(item.title, widths.title), text)
    |> Screen.put_text(x + 10 + widths.title, y, pad(column(item), widths.column), @column)
    |> Screen.put_text(
      x + 10 + widths.title + widths.column,
      y,
      pad(item.repo || "", widths.repo),
      @repo
    )
  end

  # A draft has no state and no number, so it is marked as the odd one out
  # rather than pretending to be an open issue.
  defp glyph(%Item{kind: :draft}), do: "· "
  defp glyph(%Item{kind: :pull_request, state: :merged}), do: "⬤ "
  defp glyph(%Item{kind: :pull_request}), do: "⇅ "
  defp glyph(%Item{state: :closed}), do: "○ "
  defp glyph(%Item{}), do: "● "

  defp glyph_style(%Item{kind: :draft}), do: @draft
  defp glyph_style(%Item{state: state}) when state in [:closed, :merged], do: @closed
  defp glyph_style(%Item{}), do: @open

  defp number(%Item{number: nil}), do: "      "
  defp number(%Item{number: number}), do: String.pad_leading("##{number} ", 6)

  defp column(%Item{column: nil}), do: "—"
  defp column(%Item{column: column}), do: column

  defp pad(_text, width) when width <= 0, do: ""

  defp pad(text, width) do
    text
    |> Text.sanitize()
    |> Screen.truncate(width - 1)
    |> String.pad_trailing(width)
  end

  defp counter_width(state) do
    String.length(counter_text(state)) + 2
  end

  defp counter(screen, state, rect) do
    Screen.put_text_right(screen, rect, rect.y, counter_text(state), @count)
  end

  defp counter_text(%{loading?: true, items: []}), do: "…"

  defp counter_text(state) do
    shown = length(state.shown)
    total = length(state.items)

    if shown == total, do: "#{total}", else: "#{shown}/#{total}"
  end

  # ## State

  # The loader is a function in the state rather than a call to Github, which
  # is what lets a test mount this view against a board it made up. It answers
  # {:ok, items} or {:error, message} — the shape handle_event/2 already takes,
  # and the shape Atui.Fetch turns a crash into.
  defp load(state) do
    Fetch.start(__MODULE__, :items, state.loader)

    assign(state, loading?: true, error: nil)
  end

  defp search(state) do
    state
    |> assign(:filter, Filter.put_query(state.filter, TextInput.value(state.input)))
    |> refilter()
  end

  # The selection follows the card, not the row number: narrowing a list under
  # a selection that stayed put would leave it pointing at something else.
  defp refilter(state) do
    shown = Filter.apply(state.filter, state.items)

    cursor =
      case Enum.find_index(shown, &(&1.id == state.selected_id)) do
        nil -> min(state.cursor, max(0, length(shown) - 1))
        index -> index
      end

    state
    |> assign(:shown, shown)
    |> put_cursor(cursor)
  end

  defp move(state, by), do: put_cursor(state, state.cursor + by)

  defp put_cursor(state, cursor) do
    cursor = cursor |> max(0) |> min(max(0, length(state.shown) - 1))

    assign(state,
      cursor: cursor,
      selected_id: with(%Item{id: id} <- Enum.at(state.shown, cursor), do: id)
    )
  end

  # Nothing to show is not an error worth a message: an empty list has no card
  # under the cursor, and the key simply does nothing.
  defp detail(state) do
    case selected(state) do
      nil -> {:ok, state}
      item -> {:push, Detail, [item: item], assign(state, :popup?, true)}
    end
  end

  @doc """
  The filter with the switches the cards themselves decide.

  The columns come from the board, so they are known before anything loads. The
  states, labels and assignees are only what the cards happen to show — a board
  with no pull requests on it has no "merged" switch to offer — so they are read
  off the cards each time they arrive. Switches already set are kept, which is
  what makes a reload keep the filter.
  """
  @spec observed(Filter.t(), [Item.t()]) :: Filter.t()
  def observed(%Filter{} = filter, items) do
    states =
      Enum.filter(Item.state_keys(), fn key -> Enum.any?(items, &(Item.state_key(&1) == key)) end)

    filter
    |> Filter.put_options(:state, states)
    |> Filter.put_options(:label, collect(items, & &1.labels))
    |> Filter.put_options(:assignee, collect(items, & &1.assignees))
  end

  defp collect(items, fun) do
    items |> Enum.flat_map(fun) |> Enum.uniq() |> Enum.sort()
  end

  defp selected(state), do: Enum.at(state.shown, state.cursor)

  defp open_selected(state) do
    case selected(state) do
      %Item{url: url} when is_binary(url) ->
        Fetch.start(__MODULE__, :open, fn -> Browser.open(url) end)
        state

      %Item{} ->
        notice(state, "a draft card has nothing to open")

      nil ->
        state
    end
  end

  defp notice(state, message) do
    Atui.Runtime.schedule_event_to(__MODULE__, :clear_notice, @notice_ms)

    assign(state, notice: message, error: nil)
  end
end
