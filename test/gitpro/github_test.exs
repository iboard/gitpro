defmodule Gitpro.GithubTest do
  use ExUnit.Case, async: true

  alias Gitpro.{Github, Item}

  # A page of items as GitHub sends it: an issue, a merged pull request, a
  # draft, a card whose content the token cannot see, and one that is in no
  # column at all.
  defp items_payload do
    %{
      "node" => %{
        "items" => %{
          "totalCount" => 5,
          "pageInfo" => %{"hasNextPage" => false, "endCursor" => "abc"},
          "nodes" => [
            %{
              "id" => "PVTI_1",
              "fieldValues" => %{
                "nodes" => [
                  %{"__typename" => "ProjectV2ItemFieldRepositoryValue"},
                  %{
                    "__typename" => "ProjectV2ItemFieldSingleSelectValue",
                    "name" => "small",
                    "field" => %{"name" => "Size"}
                  },
                  %{
                    "__typename" => "ProjectV2ItemFieldSingleSelectValue",
                    "name" => "In Progress",
                    "field" => %{"name" => "Status"}
                  }
                ]
              },
              "content" => %{
                "__typename" => "Issue",
                "number" => 42,
                "title" => "  Fix the login form  ",
                "state" => "OPEN",
                "url" => "https://github.com/acme/web/issues/42",
                "updatedAt" => "2026-09-01T10:00:00Z",
                "repository" => %{"nameWithOwner" => "acme/web"},
                "labels" => %{"nodes" => [%{"name" => "bug"}, %{"name" => "ux"}]},
                "assignees" => %{"nodes" => [%{"login" => "iboard"}]}
              }
            },
            %{
              "id" => "PVTI_2",
              "fieldValues" => %{
                "nodes" => [
                  %{
                    "__typename" => "ProjectV2ItemFieldSingleSelectValue",
                    "name" => "Done",
                    "field" => %{"name" => "Status"}
                  }
                ]
              },
              "content" => %{
                "__typename" => "PullRequest",
                "number" => 43,
                "title" => "Bump deps",
                "state" => "MERGED",
                "url" => "https://github.com/acme/web/pull/43",
                "repository" => %{"nameWithOwner" => "acme/web"},
                "labels" => %{"nodes" => []},
                "assignees" => %{"nodes" => []}
              }
            },
            %{
              "id" => "PVTI_3",
              "fieldValues" => %{"nodes" => []},
              "content" => %{"__typename" => "DraftIssue", "title" => "Think about caching"}
            },
            %{"id" => "PVTI_4", "fieldValues" => %{"nodes" => []}, "content" => %{}},
            %{
              "id" => "PVTI_5",
              "fieldValues" => %{
                "nodes" => [
                  %{
                    "__typename" => "ProjectV2ItemFieldSingleSelectValue",
                    "name" => "large",
                    "field" => %{"name" => "Size"}
                  }
                ]
              },
              "content" => %{
                "__typename" => "Issue",
                "number" => 44,
                "title" => "Untriaged",
                "state" => "CLOSED",
                "url" => "https://github.com/acme/web/issues/44",
                "repository" => %{"nameWithOwner" => "acme/web"},
                "labels" => %{"nodes" => []},
                "assignees" => %{"nodes" => []}
              }
            }
          ]
        }
      }
    }
  end

  describe "decode_items/1" do
    test "an issue becomes a card with everything the list draws" do
      assert [issue | _] = Github.decode_items(items_payload())

      assert %Item{
               id: "PVTI_1",
               kind: :issue,
               number: 42,
               title: "Fix the login form",
               state: :open,
               url: "https://github.com/acme/web/issues/42",
               repo: "acme/web",
               column: "In Progress",
               labels: ["bug", "ux"],
               assignees: ["iboard"]
             } = issue
    end

    test "the Status field is the column, whatever order the values arrive in" do
      assert [%Item{column: "In Progress"} | _] = Github.decode_items(items_payload())
    end

    test "a card in no column has none, rather than borrowing another field's" do
      assert %Item{column: nil, state: :closed} =
               items_payload() |> Github.decode_items() |> Enum.find(&(&1.number == 44))
    end

    test "a board that renamed its field is read under that name" do
      assert [%Item{column: "small"} | _] = Github.decode_items(items_payload(), "Size")
    end

    test "a board with no single-select field puts every card in no column" do
      assert Enum.all?(Github.decode_items(items_payload(), nil), &is_nil(&1.column))
    end

    test "a merged pull request keeps its own state" do
      assert %Item{kind: :pull_request, state: :merged, column: "Done"} =
               items_payload() |> Github.decode_items() |> Enum.at(1)
    end

    test "a draft has a title and nothing else" do
      assert %Item{
               kind: :draft,
               number: nil,
               url: nil,
               state: :none,
               title: "Think about caching"
             } =
               items_payload() |> Github.decode_items() |> Enum.at(2)
    end

    test "a card whose content cannot be seen is dropped rather than drawn blank" do
      ids = items_payload() |> Github.decode_items() |> Enum.map(& &1.id)

      refute "PVTI_4" in ids
      assert length(ids) == 4
    end

    test "every card comes back searchable" do
      for item <- Github.decode_items(items_payload()) do
        assert is_binary(item.search)
        assert item.search == String.downcase(item.search)
      end

      assert [issue | _] = Github.decode_items(items_payload())
      assert issue.search =~ "#42"
      assert issue.search =~ "bug"
      assert issue.search =~ "acme/web"
    end

    test "a payload with nothing in it decodes to nothing" do
      assert Github.decode_items(%{}) == []
      assert Github.decode_items(%{"node" => %{}}) == []
    end
  end

  describe "decode_board/2" do
    test "the Status field's options are the columns, in board order" do
      data = %{
        "node" => %{
          "title" => "e-Matrix System",
          "number" => 13,
          "url" => "https://github.com/orgs/acme/projects/13",
          "fields" => %{
            "nodes" => [
              %{},
              %{"name" => "Size", "options" => [%{"name" => "small"}]},
              %{
                "name" => "Status",
                "options" => [%{"name" => "Backlog"}, %{"name" => "Ready"}, %{"name" => "Done"}]
              }
            ]
          }
        }
      }

      assert Github.decode_board("PVT_1", data) == %{
               id: "PVT_1",
               number: 13,
               title: "e-Matrix System",
               url: "https://github.com/orgs/acme/projects/13",
               column_field: "Status",
               columns: ["Backlog", "Ready", "Done"]
             }
    end

    test "a board that renamed Status falls back to its first single-select" do
      data = %{
        "node" => %{
          "fields" => %{"nodes" => [%{"name" => "Stage", "options" => [%{"name" => "Doing"}]}]}
        }
      }

      assert %{columns: ["Doing"], column_field: "Stage"} = Github.decode_board("PVT_1", data)
    end

    test "a board with no single-select field has no columns" do
      assert %{columns: [], column_field: nil, title: "project"} =
               Github.decode_board("PVT_1", %{"node" => %{"fields" => %{"nodes" => [%{}]}}})
    end
  end

  describe "decode_projects/1" do
    test "open boards come first, each keeping the board's own order" do
      data = %{
        "repository" => %{
          "projectsV2" => %{
            "nodes" => [
              %{"id" => "a", "number" => 14, "title" => "old", "closed" => true, "url" => "u1"},
              %{"id" => "b", "number" => 13, "title" => "live", "closed" => false, "url" => "u2"},
              %{"id" => "c", "number" => 15, "title" => "also", "closed" => false, "url" => "u3"}
            ]
          }
        }
      }

      assert [%{number: 13}, %{number: 15}, %{number: 14}] = Github.decode_projects(data)
    end

    test "a repository on no board decodes to an empty list" do
      assert Github.decode_projects(%{"repository" => %{"projectsV2" => %{"nodes" => []}}}) == []
      assert Github.decode_projects(%{}) == []
    end

    test "a board with no title is still listed" do
      data = %{"repository" => %{"projectsV2" => %{"nodes" => [%{"id" => "a", "number" => 1}]}}}

      assert [%{title: "untitled project", closed: false}] = Github.decode_projects(data)
    end
  end
end
