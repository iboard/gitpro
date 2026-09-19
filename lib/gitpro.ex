defmodule Gitpro do
  @moduledoc """
  A terminal browser for the issues on a GitHub project board.

  `gitpro` is run from inside a checkout: it asks git which repository that is,
  asks GitHub which Projects v2 boards the repository is on, and opens a list of
  everything on the board — searchable as you type, and filterable by state and
  by kanban column.

  The pieces:

  | Module | |
  | --- | --- |
  | `Gitpro.CLI` | argument parsing, and everything that has to work before the screen is taken over |
  | `Gitpro.Git` | which repository the working directory belongs to |
  | `Gitpro.Github` | the `gh` GraphQL calls, and pure decoders for what they answer |
  | `Gitpro.Item` | one card on the board |
  | `Gitpro.Filter` | what is shown, as data — query, states, columns |
  | `Gitpro.Views.Issues` | the list, the search field and the footer |
  | `Gitpro.Views.Filters` | the popup of on/off flags |

  Everything that decides *what* is on screen is a pure function over data, so
  the interesting half of the application is tested without a terminal and
  without the network.
  """

  @version Mix.Project.config()[:version]

  @doc "The version of gitpro, as a string."
  def version, do: @version
end
