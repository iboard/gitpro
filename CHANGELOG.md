# Changelog

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
