defmodule Gitpro.Browser do
  @moduledoc """
  Opens a URL in whatever this desktop calls a browser.

  `$BROWSER` first, because someone who set it meant it, then `xdg-open`, then
  the macOS `open` — the first one that exists on the PATH wins.

  The command is run detached from the terminal, with its output on `/dev/null`:
  a browser that decides to log a GTK warning would otherwise write it straight
  over the frame the UI has drawn, on a terminal that is in raw mode and will
  not scroll it away.
  """

  @doc """
  Opens `url`, answering `:ok` or `{:error, message}`.

  It blocks until the opener returns, which is quick but not instant — call it
  from an `Atui.Fetch`, not from a view callback.
  """
  @spec open(String.t()) :: :ok | {:error, String.t()}
  def open(url) when is_binary(url) do
    case opener() do
      nil ->
        {:error, "no browser to open it with — set $BROWSER, or install xdg-open"}

      command ->
        case System.cmd("sh", ["-c", "#{command} #{shell_quote(url)} >/dev/null 2>&1 &"]) do
          {_output, 0} -> :ok
          {_output, status} -> {:error, "#{command} exited with #{status}"}
        end
    end
  end

  def open(nil), do: {:error, "this card has nothing to open — it is a draft"}

  defp opener do
    candidates = [System.get_env("BROWSER"), "xdg-open", "open"]

    Enum.find(
      candidates,
      &(is_binary(&1) and &1 != "" and System.find_executable(hd(String.split(&1))) != nil)
    )
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
