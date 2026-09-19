# gitpro

Browse a GitHub **project board** from the terminal, from inside the checkout it
belongs to.

```sh
cd ~/Projects/some-repo
gitpro
```

It asks git which repository that is, asks GitHub which Projects v2 boards the
repository is linked to, and opens the cards on one: searchable as you type, and
filterable by state and by kanban column.

```
┌──────────────────── gitpro · e-matrix/eec · #13 e-Matrix System ─────────────────────┐
│report                                                                                │
│──────────────────────────────────────────────────────────────────────────────────────│
│▌ ●  #382 20260911-07 placeholder - Report filter        Grooming      e-matrix/eec    │
│  ●  #385 20260911-11 placeholder - Team leader report   Grooming      e-matrix/eec    │
│                                                                                      │
│^I details   ^O open   ^F filter   ^R reload   ESC quit                           2/18│
└──────────────────────────────────────────────────────────────────────────────────────┘
```

## Keys

Typing searches. There is no mode to enter and no key to press first — the
search field has the keyboard from the moment gitpro opens, so every printable
character is the query's and everything else is bound to a key the field does
not want.

| | |
| --- | --- |
| *type* | search, as you type — every word has to match |
| `^I` | the selected card in full |
| `^O` `⏎` | open the selected card in a browser |
| `^F` | the filter switches |
| `↑` `↓` `^P` `^N` | move the selection |
| `PgUp` `PgDn` | a screen at a time |
| `^R` | reload the board |
| `ESC` | clear the search, then quit |
| `^C` | quit |

`^I` is the byte the Tab key sends — a terminal cannot tell the two apart — so
Tab opens the card too. `q` is a letter, so in the list it goes into the search
field like anything else; in the popups, where there is nothing to type into, it
closes.

### The card

`^I` opens a centred popup with the card's title, description, state, column,
repository, author, labels, assignees, milestone and dates. Everything in it was
fetched with the board, so it opens instantly and keeps working with the network
gone — including the card it moves to next.

| | |
| --- | --- |
| `↑` `↓` `j` `k` `^P` `^N` | the next or previous card, without closing |
| `PgUp` `PgDn` `^U` `^D` | scroll a long description |
| `Home` | back to the top |
| `^O` `⏎` | open the card in a browser |
| `ESC` `q` `^I` | close |

`j` and `k` walk the list with the popup still open, which is what reading
through a column is: open the first card, keep pressing `j`. The popup does not
hold the list — it asks the list view to move its selection and is handed back
whatever is now selected. So the selection behind the popup moves with it, the
search and the switches still decide what "next" means, and closing leaves the
cursor on the card you stopped at.

### The switches

`^F` opens the filter, which has a group per axis:

* **State** — `open`, `closed`, `merged`, `draft`. Only the states the board
  actually has get a switch, so a board of nothing but issues is not offered a
  `merged` one. A merged pull request is its own state rather than a closed one.
* **Columns** — one per column of the board's kanban field, plus `No column`.
* **Labels** — one per label any card wears, plus `Unlabelled`.
* **Assignees** — one per person any card is assigned to, plus `Unassigned`.

`SPACE` toggles the switch under the cursor, `a` turns them all on, `n` turns
them all off, `ESC` or `q` closes. The list narrows behind the popup as the switches
are set, so you can see what a switch does before you commit to it.

Everything starts on. The groups combine — a card is shown when it passes every
axis *and* the search. Within a group a card can hold several values (two
labels, two assignees) and passes while **any** of them is on, so turning one
label off hides the cards that wear only that label, not every card wearing it.

Columns come from the board, so an empty column is still a switch. States,
labels and assignees come from the cards, so they appear once the board has
loaded — a filter popup left open while that happens grows the new groups where
it stands.

## Options

```
gitpro                     the board of the repository you are standing in
gitpro --project 13        that board, when the repository is on several
gitpro --repo owner/name   somewhere other than here
gitpro --list              the boards this repository is on, and stop
```

Without `--project`, the repository's first **open** board is opened, and a note
on stderr names the others when there is more than one.

## Installing

`gitpro` talks to GitHub through the [`gh`](https://cli.github.com) CLI, which
must be installed and logged in with the `project` scope:

```sh
gh auth login
gh auth refresh -s project      # if 'project' is not already in gh auth status
```

Then build the binary. It is an escript — one self-contained file that runs
wherever it is called from:

```sh
git clone https://github.com/iboard/gitpro.git
cd gitpro
mix deps.get
mix escript.build         # ./gitpro
mix escript.install       # ~/.mix/escripts/gitpro, put that on your PATH
```

`bin/gitpro` runs it from the source tree, rebuilding when the sources have
changed — handy while working on it, and still correct about the directory it
was called from:

```sh
cd ~/Projects/some-repo && ~/Projects/gitpro/bin/gitpro
```

## How it is put together

The UI is [Atui](https://github.com/iboard/atui), a terminal toolkit in the
shape of Phoenix LiveView: views with state, a `render/2` that returns cells,
and a runtime that owns the terminal. It comes from Hex; to work on both at
once, point the dependency in `mix.exs` back at a local checkout:

```elixir
{:atui, path: "../atui"}
```

| Module | |
| --- | --- |
| `Gitpro.CLI` | arguments, and everything that has to work before the screen is taken over |
| `Gitpro.Git` | which repository the working directory belongs to |
| `Gitpro.Github` | the `gh` GraphQL calls, and pure decoders for what they answer |
| `Gitpro.Item` | one card on the board |
| `Gitpro.Filter` | what is shown, as data — query, states, columns |
| `Gitpro.Views.Issues` | the list, the search field and the footer |
| `Gitpro.Views.Filters` | the popup of on/off switches |
| `Gitpro.Views.Detail` | the popup showing one card in full |
| `Gitpro.Window` | which row a list taller than its box starts at |

Two things are deliberate:

**Failing happens in the terminal, not in the UI.** "Not a git repository", "gh
is not installed", "this repository is not on a project board" are printed on
stderr with a non-zero exit status, before the alternate screen is opened. Only
the slow call — the cards themselves — is left to the view, which draws its
first frame before any of them have arrived and stays usable while they load.

**Everything that decides what is on screen is a pure function over data.**
`Gitpro.Filter.apply/2`, the GraphQL decoders, the row widths, the window onto a
list longer than the screen, the rows a card turns into in the detail popup. So
the interesting half of the application is tested without a terminal, and
without a token:

```sh
mix test
```

## Not yet

An MVP, and it shows. The obvious next things:

* comments and sub-issues in the detail popup, which today shows the card itself
* moving a card between columns from here, rather than in a browser
* remembering the switches per board between runs
* searching the description text, which today is deliberately not searched
* `--project` by title as well as by number

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).

Copyright (C) 2026 Andreas Altendorfer

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

[Atui](https://github.com/iboard/atui), the toolkit this is built on, is
Apache-2.0, which GPLv3 is compatible with.
