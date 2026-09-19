defmodule Gitpro.GitTest do
  use ExUnit.Case, async: true

  alias Gitpro.Git

  describe "parse_remote/1" do
    test "reads owner and name out of every shape of GitHub remote" do
      for url <- [
            "git@github.com:iboard/atui.git",
            "git@github.com:iboard/atui",
            "ssh://git@github.com/iboard/atui.git",
            "https://github.com/iboard/atui.git",
            "https://github.com/iboard/atui",
            "https://iboard@github.com/iboard/atui.git",
            "  https://github.com/iboard/atui.git\n"
          ] do
        assert Git.parse_remote(url) == {:ok, %{owner: "iboard", name: "atui"}},
               "could not parse #{url}"
      end
    end

    test "an SSH config alias is still github.com" do
      assert Git.parse_remote("git@github.com-work:acme/thing.git") ==
               {:ok, %{owner: "acme", name: "thing"}}
    end

    test "a repository in a nested path takes the last two segments" do
      assert Git.parse_remote("https://github.com/iboard/atui/") ==
               {:ok, %{owner: "iboard", name: "atui"}}
    end

    test "another host is refused by name, so the message says what is wrong" do
      assert {:error, message} = Git.parse_remote("git@gitlab.com:iboard/atui.git")
      assert message =~ "gitlab.com"
      assert message =~ "GitHub"
    end

    test "a remote with nothing to read is refused" do
      assert {:error, _} = Git.parse_remote("github.com")
      assert {:error, _} = Git.parse_remote("")
      assert {:error, _} = Git.parse_remote("https://github.com/iboard")
    end
  end

  describe "repo/1" do
    test "a directory that is not a repository says so" do
      assert {:error, message} = Git.repo(System.tmp_dir!())
      assert message =~ "not a git repository"
    end
  end
end
