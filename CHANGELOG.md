# Changelog

## 1.0.0

The first stable release. Everything in 0.1.0, and:

* `^A` opens an **about popup**: what this is, which version of it, and the
  links to GitHub, Hex and HexDocs. The links are a list you move through with
  `↑` `↓` `j` `k`, and `⏎` opens the highlighted one in a browser.

`^A` was readline's "start of the line" in the search field, which
`Atui.TextInput` still binds; `Home` does that now.

## 0.1.0

First release.

Browse a GitHub Projects v2 board from inside the checkout it belongs to:
`gitpro` asks git which repository you are standing in, asks GitHub which boards
it is linked to, and opens the cards on one.

* **Search as you type.** No mode to enter — the search field has the keyboard
  from the moment the UI opens. Every word has to match somewhere in the row:
  its number, title, repository, column, author, milestone, labels, assignees,
  state or kind.
* **Filter switches** (`^F`) on four axes: state (`open`, `closed`, `merged`,
  `draft`, only the ones the board has), the board's kanban columns, the labels
  the cards wear and the people they are assigned to — each with an empty
  bucket of its own. The list narrows behind the popup as the switches are set.
* **A card in full** (`^I`): title, description, state, column, repository,
  author, labels, assignees, milestone and dates, in a centred popup. `j` and
  `k` walk to the next and previous card without closing it, and the selection
  behind the popup moves with them.
* **Open in a browser** with `^O` or Enter, from the list or from the card.
* Errors that can be said in a terminal are said there, with a non-zero exit
  status, before the alternate screen is opened.

Built on [Atui](https://github.com/iboard/atui). Talks to GitHub through the
`gh` CLI, so there is no HTTP client, no JSON dependency and no token to
configure beyond `gh auth login`.
