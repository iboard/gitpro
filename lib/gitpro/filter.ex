defmodule Gitpro.Filter do
  @moduledoc """
  What is shown, as data.

  A filter is a query string and a set of switches on four axes — the card's
  state, its column on the board, its labels and its assignees. `apply/2` is a
  pure function from a filter and every card to the cards that pass it, which is
  the whole of the filtering logic and is tested without a terminal or a network
  in sight.

  ## The query

  Whitespace splits the query into terms and *every* term has to match
  somewhere in the row — its number, title, repository, column, author,
  milestone, labels, assignees, state or kind. That makes narrowing additive:
  typing another word can only ever shorten the list, which is what a search
  field that filters as you type has to do to stay predictable.

      "bug ready"     both words, in any field, in any order
      "#42"           the number, because "#42" is part of the haystack
      "e-matrix/eec"  the repository, on a board that spans several

  ## The switches

  Every switch is on until it is turned off, which is why the filter stores what
  is **off** rather than what is on. A board that grows a column between one
  reload and the next, or a card that arrives wearing a label nobody has seen
  before, is then shown rather than silently dropped — the alternative is a
  filter that hides things because of a switch that did not exist yet.

  An axis is either single-valued or multi-valued, and they are filtered
  differently:

    * **state** and **column** — a card is in exactly one, so it passes when
      that one is on.
    * **labels** and **assignees** — a card can be in several, so it passes when
      *any* of them is on. Turning one label off therefore hides the cards that
      wear only that label, not every card that happens to wear it too.

  Each axis has a `:none` bucket — no column, unlabelled, unassigned — so the
  cards that nobody has got to yet are a switch of their own rather than a gap.

  ## Where the options come from

  The columns come from the board, so a column with nothing in it is still a
  switch you can turn off. The states, labels and assignees come from the cards,
  because nothing else knows what is on the board — `put_options/3` is how the
  list view hands them over once they have loaded, and it keeps the switches
  that were already set.
  """

  alias Gitpro.Item

  @axes [:state, :column, :label, :assignee]

  # The axes where "not any of them" is itself something to filter on.
  @none_axes [:column, :label, :assignee]

  defstruct query: "", options: %{}, off: MapSet.new()

  @type axis :: :state | :column | :label | :assignee
  @type key :: String.t() | atom()
  @type flag :: {axis(), key()}

  @type t :: %__MODULE__{
          query: String.t(),
          options: %{axis() => [key()]},
          off: MapSet.t(flag())
        }

  @doc "The axes, in the order the popup lists them."
  @spec axes() :: [axis()]
  def axes, do: @axes

  @doc "How an axis is titled on screen."
  @spec axis_title(axis()) :: String.t()
  def axis_title(:state), do: "State"
  def axis_title(:column), do: "Columns"
  def axis_title(:label), do: "Labels"
  def axis_title(:assignee), do: "Assignees"

  @doc """
  A filter that hides nothing, with a switch for each of the board's `columns`.

  The other three axes start empty and are filled in by `put_options/3` once the
  cards are in — until then they hide nothing, which is what an axis with no
  switches on it should do.
  """
  @spec new([String.t()]) :: t()
  def new(columns \\ []) do
    %__MODULE__{options: Map.new(@axes, &{&1, []})}
    |> put_options(:column, columns)
  end

  @doc """
  Replaces one axis's switches, keeping the ones already set.

  The `:none` bucket is appended rather than expected in `keys`: a card with no
  column, no label or no assignee is always possible, whatever the cards that
  have loaded happen to show. State has no such bucket — every card is in one of
  the states, and a switch that can never match anything is a switch that only
  wastes a row.
  """
  @spec put_options(t(), axis(), [key()]) :: t()
  def put_options(%__MODULE__{} = filter, axis, keys) when axis in @axes do
    options =
      keys
      |> Enum.reject(&(&1 in [nil, "", :none]))
      |> Enum.uniq()
      |> then(&if(axis in @none_axes, do: &1 ++ [:none], else: &1))

    %{filter | options: Map.put(filter.options, axis, options)}
  end

  @doc "The switches on `axis`, in the order they are listed."
  @spec options(t(), axis()) :: [key()]
  def options(%__MODULE__{} = filter, axis), do: Map.get(filter.options, axis, [])

  @doc "Every switch the filter knows about, as `{axis, key}` pairs."
  @spec flags(t()) :: [flag()]
  def flags(%__MODULE__{} = filter) do
    Enum.flat_map(@axes, fn axis -> Enum.map(options(filter, axis), &{axis, &1}) end)
  end

  @doc "Replaces the query string."
  @spec put_query(t(), String.t()) :: t()
  def put_query(%__MODULE__{} = filter, query) when is_binary(query) do
    %{filter | query: query}
  end

  @doc "Whether a switch is on. A switch nobody has touched is on."
  @spec on?(t(), flag()) :: boolean()
  def on?(%__MODULE__{} = filter, flag), do: not MapSet.member?(filter.off, flag)

  @doc "Flips one switch."
  @spec toggle(t(), flag()) :: t()
  def toggle(%__MODULE__{} = filter, flag) do
    off =
      if on?(filter, flag),
        do: MapSet.put(filter.off, flag),
        else: MapSet.delete(filter.off, flag)

    %{filter | off: off}
  end

  @doc """
  Turns every switch on or off at once, the query untouched.

  `set_all(filter, false)` can only turn off the switches the filter knows
  about, so a label that arrives afterwards is on — see the note on where the
  options come from.
  """
  @spec set_all(t(), boolean()) :: t()
  def set_all(%__MODULE__{} = filter, true), do: %{filter | off: MapSet.new()}

  def set_all(%__MODULE__{} = filter, false) do
    %{filter | off: MapSet.new(flags(filter))}
  end

  @doc "True while a switch is off — the query is not counted."
  @spec flags_narrowed?(t()) :: boolean()
  def flags_narrowed?(%__MODULE__{} = filter), do: MapSet.size(filter.off) > 0

  @doc "True when this filter can remove a row at all."
  @spec narrowed?(t()) :: boolean()
  def narrowed?(%__MODULE__{} = filter) do
    String.trim(filter.query) != "" or flags_narrowed?(filter)
  end

  @doc """
  The cards that pass the filter, in the order they were given.

  Order is the board's, not the filter's: a list that reshuffles itself as you
  type is unusable, so filtering only ever takes rows away.
  """
  @spec apply(t(), [Item.t()]) :: [Item.t()]
  def apply(%__MODULE__{} = filter, items) when is_list(items) do
    terms = terms(filter.query)

    Enum.filter(items, fn item ->
      on?(filter, {:state, Item.state_key(item)}) and
        on?(filter, {:column, Item.column_key(item)}) and
        any_on?(filter, :label, Item.label_keys(item)) and
        any_on?(filter, :assignee, Item.assignee_keys(item)) and
        matches?(item, terms)
    end)
  end

  defp any_on?(filter, axis, keys), do: Enum.any?(keys, &on?(filter, {axis, &1}))

  @doc "Splits a query into the lowercased terms every row has to match."
  @spec terms(String.t()) :: [String.t()]
  def terms(query) when is_binary(query) do
    query |> String.downcase() |> String.split(~r/\s+/, trim: true)
  end

  defp matches?(_item, []), do: true

  defp matches?(%Item{} = item, terms) do
    haystack = item.search || Item.searchable(item)

    Enum.all?(terms, &String.contains?(haystack, &1))
  end

  @doc """
  A one-line description of the switches, for the footer.

  Answers `nil` when nothing is narrowed, so the footer can leave the space to
  the shortcuts rather than saying "all".
  """
  @spec summary(t()) :: String.t() | nil
  def summary(%__MODULE__{} = filter) do
    @axes
    |> Enum.map(&axis_summary(filter, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      text -> text
    end
  end

  # Whichever list is shorter is the one worth printing: with one column off out
  # of eight, "-Done" says more in less room than the seven that are on.
  defp axis_summary(filter, axis) do
    {on, off} = filter |> options(axis) |> Enum.split_with(&on?(filter, {axis, &1}))

    cond do
      off == [] -> nil
      on == [] -> "no #{axis}"
      length(on) <= length(off) -> Enum.map_join(on, ",", &label(axis, &1))
      true -> "-" <> Enum.map_join(off, ",-", &label(axis, &1))
    end
  end

  @doc """
  How a switch's key is written on screen.

  The empty bucket is named for its axis — "Unassigned" says what it holds, and
  four switches all called "(none)" would not.
  """
  @spec label(axis(), key()) :: String.t()
  def label(:column, :none), do: "No column"
  def label(:label, :none), do: "Unlabelled"
  def label(:assignee, :none), do: "Unassigned"
  def label(_axis, key), do: label(key)

  @doc "How a key is written on screen, without its axis to name it by."
  @spec label(key()) :: String.t()
  def label(:none), do: "(none)"
  def label(key) when is_atom(key), do: Atom.to_string(key)
  def label(key) when is_binary(key), do: key
end
