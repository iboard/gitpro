defmodule Gitpro.Window do
  @moduledoc """
  Which row a list that is taller than its box starts drawing at.

  Both lists here — the cards, and the flags in the popup — are longer than the
  space they get on a short terminal, and both solve it the same way: the
  selection is kept in the middle where there is room for it and pinned at
  either end where there is not.

  It is a pure function of the selection, the length and the height, so neither
  view has to keep a scroll position in its state and neither can get one out of
  step with what it is drawing.
  """

  @doc """
  The index of the first row to draw.

  A window that only moved when the selection was about to leave it would make
  the first and last rows cost an extra key to reach; pinning at the ends is
  what stops the list scrolling past its own edges.
  """
  @spec offset(non_neg_integer(), non_neg_integer(), integer()) :: non_neg_integer()
  def offset(_selected, _count, height) when height <= 0, do: 0

  def offset(selected, count, height) do
    selected
    |> Kernel.-(div(height - 1, 2))
    |> max(0)
    |> min(max(0, count - height))
  end
end
