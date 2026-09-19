defmodule Gitpro.Views.About do
  @moduledoc """
  What this is, which version of it, and where to find the rest of it.

  Opened with `^A`. The links are a list you move through rather than text you
  have to copy out of a terminal by hand — `⏎` opens the highlighted one in a
  browser, the same way `^O` opens a card.

      ↑ ↓ j k ^P ^N   move between the links    ⏎ ^O    open the highlighted one
      ESC q ^A        close

  ## The key it took

  `^A` is readline's "start of the line", and `Atui.TextInput` binds it as such.
  Claiming it here takes it off the search field, which still has `Home` for the
  same thing — a trade worth making once, for the one key that is conventionally
  "about".
  """

  use Atui.View

  import Atui.View, only: [assign: 3]

  alias Atui.{Fetch, Style, Text}
  alias Gitpro.Browser

  @border Style.new(fg: :bright_green)
  @title_style Style.new(fg: :bright_green, bold: true)
  @name Style.new(fg: :bright_white, bold: true)
  @version_style Style.new(fg: :bright_black)
  @blurb Style.new(fg: :white)
  @link_label Style.new(fg: :bright_yellow)
  @url Style.new(fg: :bright_blue)
  @selected_url Style.new(fg: :bright_blue, bold: true, underline: true)
  @cursor Style.new(fg: :bright_green, bold: true)
  @footnote Style.new(fg: :bright_black)
  @help Style.new(fg: :bright_black)
  @notice Style.new(fg: :bright_green)
  @error Style.new(fg: :bright_red, bold: true)

  @previous [:up, {:char, "k"}, {[:ctrl], "p"}]
  @next [:down, {:char, "j"}, {[:ctrl], "n"}]

  @width 62
  @notice_ms 2_500

  @links [
    {"GitHub", "https://github.com/iboard/gitpro"},
    {"Hex", "https://hex.pm/packages/gitpro"},
    {"Docs", "https://hexdocs.pm/gitpro"}
  ]

  @blurb_text "Browse a GitHub project board from the terminal."

  @doc "Where the rest of gitpro lives, in the order the popup lists them."
  @spec links() :: [{String.t(), String.t()}]
  def links, do: @links

  @impl true
  def mount(_opts), do: {:ok, %{cursor: 0, notice: nil, error: nil}}

  # A blank row, the name, the version, a blank, the blurb, a blank, the links,
  # a blank, the credits, a blank and the footer — plus the two border rows.
  @chrome 13

  @impl true
  def place(_state, viewport) do
    Rect.centered(
      viewport,
      min(@width, max(0, viewport.width - 4)),
      min(length(@links) + @chrome, max(0, viewport.height - 2))
    )
  end

  # ^A closes it again, the way ^I closes the card popup.
  @impl true
  def handle_key(key, state) when key in [:esc, {:char, "q"}, {[:ctrl], "a"}] do
    {:pop, state}
  end

  def handle_key(key, state) when key in @previous, do: {:ok, move(state, -1)}
  def handle_key(key, state) when key in @next, do: {:ok, move(state, 1)}

  def handle_key(key, state) when key in [:enter, {[:ctrl], "o"}], do: {:ok, open(state)}

  # A popup is modal: a key it has no use for does nothing, rather than reaching
  # the search field behind it.
  def handle_key(_key, state), do: {:ok, state}

  @impl true
  def handle_event({:open, :ok}, state), do: {:ok, notice(state, "opened in your browser")}

  def handle_event({:open, {:error, message}}, state) do
    {:ok, assign(state, :error, message)}
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

    Screen.new(rect.width, rect.height)
    |> Screen.box(rect,
      title: " about ",
      chars: :round,
      style: @border,
      title_style: @title_style
    )
    |> heading(body)
    |> link_rows(state, body)
    |> footnotes(body)
    |> Screen.put_text_centered(
      body,
      body.y + body.height - 1,
      footer(state, body.width),
      footer_style(state)
    )
  end

  @doc """
  The credit lines under the links.

  The dependency is named because it is the interesting half of how this looks
  the way it does, and its licence is named because it is not this one's.
  """
  @spec footnote_lines() :: [String.t()]
  def footnote_lines do
    [
      "GPL-3.0-or-later · built on Atui, which is Apache-2.0",
      "© 2026 Andreas Altendorfer"
    ]
  end

  defp heading(screen, body) do
    screen
    |> Screen.put_text_centered(body, body.y + 1, "gitpro", @name)
    |> Screen.put_text_centered(body, body.y + 2, Gitpro.version(), @version_style)
    |> Screen.put_text_centered(
      body,
      body.y + 4,
      Screen.truncate(@blurb_text, body.width),
      @blurb
    )
  end

  # The label column is fixed so the URLs line up under one another, which is
  # what makes a list of them read as a list rather than as a paragraph.
  defp link_rows(screen, state, body) do
    @links
    |> Enum.with_index()
    |> Enum.reduce(screen, fn {{label, url}, index}, acc ->
      y = body.y + 6 + index
      selected? = index == state.cursor

      acc
      |> Screen.put_text(body.x, y, if(selected?, do: "▌ ", else: "  "), @cursor)
      |> Screen.put_text(body.x + 2, y, String.pad_trailing(label, 8), @link_label)
      |> Screen.put_text(
        body.x + 10,
        y,
        Screen.truncate(url, max(0, body.width - 10)),
        if(selected?, do: @selected_url, else: @url)
      )
    end)
  end

  # Anchored to the bottom rather than measured from the top, so that a popup
  # clamped to a short terminal loses a blank row rather than printing the
  # credits over the row that says how to close it.
  defp footnotes(screen, body) do
    lines = footnote_lines()

    lines
    |> Enum.with_index(body.y + body.height - 2 - length(lines))
    |> Enum.reduce(screen, fn {line, y}, acc ->
      Screen.put_text_centered(acc, body, y, Screen.truncate(line, body.width), @footnote)
    end)
  end

  defp footer(%{error: error}, width) when is_binary(error),
    do: Screen.truncate("! " <> error, width)

  defp footer(%{notice: notice}, width) when is_binary(notice) do
    Screen.truncate("✓ " <> notice, width)
  end

  defp footer(_state, width) do
    Text.first_fitting(["⏎ open   ↑↓ move   ESC close", "⏎  ↑↓  ESC", "ESC"], width)
  end

  defp footer_style(%{error: error}) when is_binary(error), do: @error
  defp footer_style(%{notice: notice}) when is_binary(notice), do: @notice
  defp footer_style(_state), do: @help

  defp move(state, by) do
    last = length(@links) - 1

    assign(state, :cursor, state.cursor |> Kernel.+(by) |> max(0) |> min(last))
  end

  defp open(state) do
    {_label, url} = Enum.at(@links, state.cursor)

    Fetch.start(__MODULE__, :open, fn -> Browser.open(url) end)

    state
  end

  defp notice(state, message) do
    Atui.Runtime.schedule_event_to(__MODULE__, :clear_notice, @notice_ms)

    state |> assign(:notice, message) |> assign(:error, nil)
  end
end
