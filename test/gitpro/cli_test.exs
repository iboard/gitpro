defmodule Gitpro.CLITest do
  use ExUnit.Case, async: false

  alias Gitpro.CLI

  describe "repo/1" do
    test "--repo takes an owner/name" do
      assert CLI.repo(repo: "acme/web") == {:ok, %{owner: "acme", name: "web"}}
    end

    test "--repo without a slash says what it wanted" do
      assert {:error, message} = CLI.repo(repo: "web")
      assert message =~ "owner/name"

      assert {:error, _} = CLI.repo(repo: "")
      assert {:error, _} = CLI.repo(repo: "a/b/c")
    end

    test "without the switch, the working directory decides" do
      dir = Path.join(System.tmp_dir!(), "gitpro-cli-test-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      {_, 0} = System.cmd("git", ["init", "-q", dir])

      {_, 0} =
        System.cmd("git", ["-C", dir, "remote", "add", "origin", "git@github.com:acme/web.git"])

      File.cd!(dir, fn -> assert CLI.repo([]) == {:ok, %{owner: "acme", name: "web"}} end)
    end
  end
end
