defmodule Gitpro.Git do
  @moduledoc """
  Which GitHub repository the working directory belongs to.

  `gitpro` takes no repository argument in the usual case: you are standing in a
  checkout, and that is the answer. So the directory is handed to `git` and the
  `origin` remote it reports is parsed into an owner and a name.

  Remotes come in more shapes than one:

      git@github.com:owner/repo.git
      ssh://git@github.com/owner/repo.git
      https://github.com/owner/repo.git
      https://user@github.com/owner/repo

  `parse_remote/1` takes all of them, and is a pure function — the part worth
  testing is the parsing, not the shelling out.
  """

  @type repo :: %{owner: String.t(), name: String.t()}

  @doc """
  The repository the directory `dir` is a checkout of.

  Answers `{:error, message}` rather than raising: a message that can be printed
  before the UI starts is more use than a stack trace, and every way this fails
  — not a repository, no remote, a remote that is not GitHub — is something the
  person at the keyboard can act on.
  """
  @spec repo(Path.t()) :: {:ok, repo()} | {:error, String.t()}
  def repo(dir) do
    with {:ok, url} <- remote_url(dir) do
      parse_remote(url)
    end
  end

  @doc """
  The URL of the `origin` remote of the repository at `dir`.
  """
  @spec remote_url(Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def remote_url(dir) do
    case git(dir, ["remote", "get-url", "origin"]) do
      {url, 0} ->
        {:ok, String.trim(url)}

      {output, _status} ->
        if String.contains?(output, "not a git repository") do
          {:error, "#{dir} is not a git repository — run gitpro from a checkout"}
        else
          {:error, "git has no 'origin' remote here: #{String.trim(output)}"}
        end
    end
  end

  @doc """
  Turns a remote URL into `{:ok, %{owner:, name:}}`.

  The `.git` suffix is optional, the scheme may be missing, and any user
  information in front of the host is ignored — what matters is the last two
  path segments of a github.com URL.
  """
  @spec parse_remote(String.t()) :: {:ok, repo()} | {:error, String.t()}
  def parse_remote(url) when is_binary(url) do
    url
    |> String.trim()
    |> strip_scheme()
    |> split_host()
    |> case do
      {host, path} -> build(url, host, path)
      :error -> {:error, "cannot read a repository out of the remote #{inspect(url)}"}
    end
  end

  # scp-style remotes have no scheme at all, so the host is split off at the
  # colon rather than the slash; everything else is a URL.
  defp strip_scheme(url) do
    case String.split(url, "://", parts: 2) do
      [_scheme, rest] -> rest
      [rest] -> rest
    end
  end

  defp split_host(rest) do
    rest = rest |> String.split("@", parts: 2) |> List.last()

    case String.split(rest, [":", "/"], parts: 2) do
      [host, path] -> {host, path}
      _ -> :error
    end
  end

  defp build(url, host, path) do
    segments =
      path
      |> String.trim_leading("/")
      |> String.replace_suffix(".git", "")
      |> String.split("/", trim: true)

    cond do
      not github?(host) ->
        {:error, "#{host} is not github.com — gitpro only speaks to GitHub"}

      length(segments) >= 2 ->
        [name, owner | _] = Enum.reverse(segments)
        {:ok, %{owner: owner, name: name}}

      true ->
        {:error, "cannot read owner/name out of the remote #{inspect(url)}"}
    end
  end

  # An SSH config alias — `git@github.com-work:owner/repo` — is the usual way of
  # holding two GitHub accounts at once, and still github.com.
  defp github?(host) do
    host == "github.com" or String.starts_with?(host, "github.com-") or
      String.ends_with?(host, ".github.com")
  end

  defp git(dir, args) do
    System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
  rescue
    ErlangError -> {"git is not installed", 1}
  end
end
