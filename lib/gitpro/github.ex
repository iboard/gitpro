defmodule Gitpro.Github do
  @moduledoc """
  The GraphQL half: what a board is, and what is on it.

  Projects v2 has no REST endpoint worth the name, so every question here is a
  GraphQL one, asked through the `gh` CLI rather than over HTTP directly. That
  is a deliberate trade: `gh` already holds the token, already refreshes it,
  already knows about enterprise hosts and `GH_TOKEN`, and a tool that is run
  from a checkout is being run by someone who has `gh` set up. The cost is a
  process per request, which against a network round trip is nothing.

  ## Impure out here, pure in there

  `projects/1` and `items/1` shell out; `decode_projects/1` and `decode_items/1`
  are pure functions over the decoded JSON. The decoders are where the shape of
  a project item actually lives — a card that points at an issue, at a pull
  request, or at nothing — so that is what the tests exercise, on captured
  payloads, with no token and no network.

  ## What is fetched

  The cards come with their bodies, in the same pass that fetches the rest. It
  is more bytes than a list needs — but opening the detail popup is then instant
  and works with the network gone, which is worth more on a board of a few
  hundred cards than the bytes are.

  ## Errors

  Nothing raises. Every call answers `{:ok, value}` or `{:error, message}`, the
  message being something to put in front of a person: `gh` not installed, not
  logged in, a repository that is not there. `Atui.Fetch` will turn a crash into
  an error too, but an error with a sentence in it is worth more than one with
  an exception in it.
  """

  alias Gitpro.Item

  @page_size 100

  # What a kanban board calls its columns, unless it renamed the field.
  @default_column_field "Status"

  @projects_query """
  query($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      projectsV2(first: 20) {
        nodes {
          id
          number
          title
          closed
          url
        }
      }
    }
  }
  """

  @board_query """
  query($id: ID!) {
    node(id: $id) {
      ... on ProjectV2 {
        title
        number
        url
        fields(first: 50) {
          nodes {
            ... on ProjectV2SingleSelectField {
              name
              options { name }
            }
          }
        }
      }
    }
  }
  """

  @items_query """
  query($id: ID!, $first: Int!, $after: String) {
    node(id: $id) {
      ... on ProjectV2 {
        items(first: $first, after: $after) {
          totalCount
          pageInfo { hasNextPage endCursor }
          nodes {
            id
            fieldValues(first: 30) {
              nodes {
                __typename
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                  field { ... on ProjectV2FieldCommon { name } }
                }
              }
            }
            content {
              __typename
              ... on Issue {
                number title state url body createdAt updatedAt
                author { login }
                milestone { title }
                repository { nameWithOwner }
                labels(first: 20) { nodes { name } }
                assignees(first: 10) { nodes { login } }
              }
              ... on PullRequest {
                number title state url body createdAt updatedAt
                author { login }
                milestone { title }
                repository { nameWithOwner }
                labels(first: 20) { nodes { name } }
                assignees(first: 10) { nodes { login } }
              }
              ... on DraftIssue {
                title body createdAt updatedAt
                creator { login }
              }
            }
          }
        }
      }
    }
  }
  """

  @type project :: %{
          id: String.t(),
          number: pos_integer(),
          title: String.t(),
          closed: boolean(),
          url: String.t()
        }

  @type board :: %{
          id: String.t(),
          number: pos_integer(),
          title: String.t(),
          url: String.t(),
          columns: [String.t()],
          column_field: String.t() | nil
        }

  @doc """
  The Projects v2 boards `repo` is linked to, open ones first.

  Order is the reason this sorts at all: a repository collects closed boards
  over the years and the one somebody wants is almost never among them, so an
  open board is always offered before a closed one. Within each, the board's own
  order is kept.
  """
  @spec projects(Gitpro.Git.repo()) :: {:ok, [project()]} | {:error, String.t()}
  def projects(%{owner: owner, name: name}) do
    with {:ok, data} <- query(@projects_query, owner: owner, name: name) do
      {:ok, decode_projects(data)}
    end
  end

  @doc "Turns the `projectsV2` payload into project maps, open boards first."
  @spec decode_projects(map()) :: [project()]
  def decode_projects(data) do
    data
    |> dig(["repository", "projectsV2", "nodes"])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        number: node["number"],
        title: node["title"] || "untitled project",
        closed: node["closed"] == true,
        url: node["url"]
      }
    end)
    |> Enum.sort_by(& &1.closed)
  end

  @doc """
  A board's title and the columns of its kanban field.

  "The kanban board" is a single-select field by convention, and by convention
  it is called Status — that is what the board view groups by, and what the
  filter's column flags are. A board that renamed it still works: the first
  single-select field is taken when there is no Status.
  """
  @spec board(String.t()) :: {:ok, board()} | {:error, String.t()}
  def board(project_id) when is_binary(project_id) do
    with {:ok, data} <- query(@board_query, id: project_id) do
      {:ok, decode_board(project_id, data)}
    end
  end

  @doc """
  Turns the board payload into a board map.

  `column_field` is the name of the field the columns came from, and it is
  carried rather than assumed: a card has a value for every field that has one,
  so reading its column means knowing which of them to read.
  """
  @spec decode_board(String.t(), map()) :: board()
  def decode_board(project_id, data) do
    node = dig(data, ["node"]) || %{}
    field = board_field(node)

    %{
      id: project_id,
      number: node["number"],
      title: node["title"] || "project",
      url: node["url"],
      column_field: field && field["name"],
      columns: options(field)
    }
  end

  # Fields that are not single-selects come back as empty objects, because the
  # query asks for nothing else about them.
  defp board_field(node) do
    fields =
      node
      |> dig(["fields", "nodes"])
      |> List.wrap()
      |> Enum.filter(&(is_map(&1) and is_list(&1["options"])))

    Enum.find(fields, &(&1["name"] == @default_column_field)) || List.first(fields)
  end

  defp options(nil), do: []

  defp options(field) do
    field["options"] |> Enum.map(& &1["name"]) |> Enum.filter(&is_binary/1)
  end

  @doc """
  Every card on the board, following the cursor until there are no more.

  A board of a few hundred cards is several round trips, so this is the call
  that belongs in an `Atui.Fetch` rather than in a view callback.
  """
  @spec items(String.t(), String.t() | nil) :: {:ok, [Item.t()]} | {:error, String.t()}
  def items(project_id, column_field \\ @default_column_field) when is_binary(project_id) do
    paginate(project_id, column_field, nil, [])
  end

  defp paginate(project_id, column_field, cursor, acc) do
    variables =
      [id: project_id, first: @page_size] ++ if(cursor, do: [after: cursor], else: [])

    case query(@items_query, variables) do
      {:ok, data} ->
        page = dig(data, ["node", "items"]) || %{}
        acc = acc ++ decode_items(data, column_field)

        if dig(page, ["pageInfo", "hasNextPage"]) == true do
          paginate(project_id, column_field, dig(page, ["pageInfo", "endCursor"]), acc)
        else
          {:ok, acc}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Turns one page of the `items` payload into `Gitpro.Item` structs.

  Cards whose content came back empty are dropped: that is what a card pointing
  at an issue in a repository the token cannot see looks like, and a row with
  no title in it is worse than no row.
  """
  @spec decode_items(map(), String.t() | nil) :: [Item.t()]
  def decode_items(data, column_field \\ @default_column_field) do
    data
    |> dig(["node", "items", "nodes"])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.flat_map(&decode_item(&1, column_field))
  end

  defp decode_item(node, column_field) do
    case node["content"] do
      content when is_map(content) and map_size(content) > 0 ->
        [
          Item.index(%Item{
            id: node["id"],
            kind: kind(content["__typename"]),
            number: content["number"],
            title: String.trim(content["title"] || "(no title)"),
            state: state(content["state"]),
            url: content["url"],
            repo: dig(content, ["repository", "nameWithOwner"]),
            column: column(node, column_field),
            body: content["body"],
            author: dig(content, ["author", "login"]) || dig(content, ["creator", "login"]),
            milestone: dig(content, ["milestone", "title"]),
            created_at: content["createdAt"],
            updated_at: content["updatedAt"],
            labels: names(content, ["labels", "nodes"], "name"),
            assignees: names(content, ["assignees", "nodes"], "login")
          })
        ]

      _ ->
        []
    end
  end

  defp kind("Issue"), do: :issue
  defp kind("PullRequest"), do: :pull_request
  defp kind(_), do: :draft

  defp state("OPEN"), do: :open
  defp state("CLOSED"), do: :closed
  defp state("MERGED"), do: :merged
  defp state(_), do: :none

  # The column is read by field name, never by position. A card carries a value
  # for every field it has one for — a size, an estimate, a priority — and
  # taking whichever single-select came first would put "large" in the column
  # of a card that is in no column at all.
  defp column(_node, nil), do: nil

  defp column(node, column_field) do
    node
    |> dig(["fieldValues", "nodes"])
    |> List.wrap()
    |> Enum.find(fn value ->
      is_map(value) and value["__typename"] == "ProjectV2ItemFieldSingleSelectValue" and
        dig(value, ["field", "name"]) == column_field
    end)
    |> case do
      nil -> nil
      value -> value["name"]
    end
  end

  defp names(content, path, key) do
    content
    |> dig(path)
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(& &1[key])
    |> Enum.filter(&is_binary/1)
  end

  @doc """
  Runs a GraphQL query through `gh` and answers its `data`.

  GraphQL answers 200 with an `errors` array rather than a status code, so the
  exit status is not enough to tell a working query from a broken one; both are
  checked, and either turns into a message.
  """
  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def query(graphql, variables \\ []) do
    args = ["api", "graphql", "-f", "query=#{graphql}"] ++ Enum.flat_map(variables, &argument/1)

    case gh(args) do
      {output, 0} -> decode(output)
      {output, _status} -> {:error, gh_error(output)}
    end
  end

  # -F types the value, which is what an Int! variable needs; -f keeps it a
  # string, which is what an ID! and a cursor need.
  defp argument({key, value}) when is_integer(value), do: ["-F", "#{key}=#{value}"]
  defp argument({key, value}), do: ["-f", "#{key}=#{value}"]

  defp decode(output) do
    case JSON.decode(output) do
      {:ok, %{"errors" => [_ | _] = errors}} -> {:error, graphql_error(errors)}
      {:ok, %{"data" => data}} when is_map(data) -> {:ok, data}
      {:ok, _other} -> {:error, "GitHub answered something that is not a GraphQL result"}
      {:error, _reason} -> {:error, "could not read GitHub's answer as JSON"}
    end
  end

  defp graphql_error(errors) do
    errors
    |> Enum.map(&(is_map(&1) && &1["message"]))
    |> Enum.filter(&is_binary/1)
    |> Enum.join("; ")
    |> case do
      "" -> "GitHub rejected the query"
      message -> message
    end
  end

  # gh puts its own diagnosis on stderr, and it is usually the right one —
  # "not logged in", "could not resolve to a Repository". Pass it through.
  defp gh_error(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "{"))
    |> Enum.join(" ")
    |> String.trim()
    |> case do
      "" -> "gh could not talk to GitHub"
      message -> message
    end
  end

  defp gh(args) do
    System.cmd("gh", args, stderr_to_stdout: true)
  rescue
    ErlangError ->
      {"gh is not installed — see https://cli.github.com, then run: gh auth login", 1}
  end

  defp dig(nil, _path), do: nil
  defp dig(value, []), do: value

  defp dig(map, [key | rest]) when is_map(map), do: dig(Map.get(map, key), rest)
  defp dig(_value, _path), do: nil
end
