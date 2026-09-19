defmodule Gitpro.Item do
  @moduledoc """
  One card on the board.

  A project item is not an issue: it is a card that *may* point at an issue, at
  a pull request, or at nothing but its own title (a draft). All three are shown
  — a board with the drafts hidden is not the board anyone is looking at — and
  `kind` says which is which.

  `column` is the card's position on the kanban board: the value of the board's
  single-select field, or `nil` for a card that has not been put in a column.

  `search` is the row flattened into one lowercased string. It is built once, at
  decode time, because the search field filters on every keystroke and a few
  hundred cards is enough for the difference to be felt. The body is not in it:
  searching the text of every issue on a board finds a great many cards that
  merely mention the word, which is a different tool than this one.

  ## Keys

  The `*_keys/1` functions are what `Gitpro.Filter` filters on, and each answers
  the key of a flag rather than the value itself. `label_keys/1` and
  `assignee_keys/1` answer `[:none]` for a card that has neither, so "unlabelled"
  and "unassigned" are flags you can turn off like any other rather than a state
  with no switch for it.
  """

  defstruct [
    :id,
    :kind,
    :number,
    :title,
    :state,
    :url,
    :repo,
    :column,
    :body,
    :author,
    :milestone,
    :created_at,
    :updated_at,
    :search,
    labels: [],
    assignees: []
  ]

  @type kind :: :issue | :pull_request | :draft
  @type state :: :open | :closed | :merged | :none
  @type state_key :: :open | :closed | :merged | :draft

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          number: pos_integer() | nil,
          title: String.t(),
          state: state(),
          url: String.t() | nil,
          repo: String.t() | nil,
          column: String.t() | nil,
          body: String.t() | nil,
          author: String.t() | nil,
          milestone: String.t() | nil,
          created_at: String.t() | nil,
          updated_at: String.t() | nil,
          search: String.t(),
          labels: [String.t()],
          assignees: [String.t()]
        }

  # The order the flags are listed in, which is the order a card travels in.
  @state_keys [:open, :closed, :merged, :draft]

  @doc "Every state a card can be in, in the order the filter lists them."
  @spec state_keys() :: [state_key()]
  def state_keys, do: @state_keys

  @doc """
  Which state flag this card answers to.

  A merged pull request is its own state rather than a closed one: on a board
  that tracks pull requests, "closed" means the ones that were given up on, and
  lumping the merged in with them hides the difference that matters. A draft is
  its own state too — it has no state of its own to report.
  """
  @spec state_key(t()) :: state_key()
  def state_key(%__MODULE__{kind: :draft}), do: :draft
  def state_key(%__MODULE__{state: :merged}), do: :merged
  def state_key(%__MODULE__{state: :closed}), do: :closed
  def state_key(%__MODULE__{}), do: :open

  @doc """
  The key this card's column is filtered under.

  Cards with no column share the `:none` bucket, which is a flag of its own so
  that "everything nobody has triaged yet" can be looked at on its own.
  """
  @spec column_key(t()) :: String.t() | :none
  def column_key(%__MODULE__{column: nil}), do: :none
  def column_key(%__MODULE__{column: column}), do: column

  @doc "The label flags this card answers to, or `[:none]` when it has none."
  @spec label_keys(t()) :: [String.t() | :none]
  def label_keys(%__MODULE__{labels: []}), do: [:none]
  def label_keys(%__MODULE__{labels: labels}), do: labels

  @doc "The assignee flags this card answers to, or `[:none]` when unassigned."
  @spec assignee_keys(t()) :: [String.t() | :none]
  def assignee_keys(%__MODULE__{assignees: []}), do: [:none]
  def assignee_keys(%__MODULE__{assignees: assignees}), do: assignees

  @doc "Builds the lowercased string `Gitpro.Filter` matches a query against."
  @spec searchable(t()) :: String.t()
  def searchable(%__MODULE__{} = item) do
    [
      if(item.number, do: "##{item.number}", else: ""),
      item.title,
      item.repo || "",
      item.column || "",
      item.author || "",
      item.milestone || "",
      Enum.join(item.labels, " "),
      Enum.join(item.assignees, " "),
      Atom.to_string(state_key(item)),
      Atom.to_string(item.kind)
    ]
    |> Enum.join(" ")
    |> String.downcase()
  end

  @doc "Fills in `search` from everything else in the struct."
  @spec index(t()) :: t()
  def index(%__MODULE__{} = item), do: %{item | search: searchable(item)}
end
