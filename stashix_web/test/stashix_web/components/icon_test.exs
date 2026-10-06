defmodule StashixWeb.UI.IconTest do
  use ExUnit.Case, async: true

  alias StashixWeb.UI.Icon

  # Lucide renames and removes icons between releases, and an unknown name
  # renders as nothing at all. This catches a dependency update that takes an
  # icon away from under a template.
  test "every lucide icon named in the web layer exists" do
    names =
      "lib/stashix_web/**/*.{ex,heex}"
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        ~r/lucide-([a-z0-9]+(?:-[a-z0-9]+)*)/
        |> Regex.scan(File.read!(file), capture: :all_but_first)
        |> List.flatten()
      end)
      |> Enum.uniq()

    assert names != []

    missing = Enum.reject(names, &Icon.lucide?/1)
    assert missing == [], "icons not in the Lucide set: #{Enum.join(missing, ", ")}"
  end
end
