# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.ReadingOrderTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Accounts, Library}
  alias Stashix.Library.{Access, Series}

  defp b(title, attrs), do: Map.merge(%{title: title, volume: nil, issue_number: nil}, attrs)
  defp titles(books), do: Enum.map(books, & &1.title)

  describe "sort_reading_order/1" do
    test "volume-only trades order by volume" do
      books = [b("Three", %{volume: 3}), b("One", %{volume: 1}), b("Two", %{volume: 2})]
      assert titles(Library.sort_reading_order(books)) == ["One", "Two", "Three"]
    end

    test "multi-volume issues order by volume, then issue" do
      books = [
        b("v2 #1", %{volume: 2, issue_number: Decimal.new(1)}),
        b("v1 #2", %{volume: 1, issue_number: Decimal.new(2)}),
        b("v1 #1", %{volume: 1, issue_number: Decimal.new(1)})
      ]

      assert titles(Library.sort_reading_order(books)) == ["v1 #1", "v1 #2", "v2 #1"]
    end

    test "a single volume orders by issue, so an untagged issue keeps its place" do
      books = [
        b("#3", %{volume: 1, issue_number: Decimal.new(3)}),
        b("#2", %{issue_number: Decimal.new(2)}),
        b("#1", %{volume: 1, issue_number: Decimal.new(1)}),
        b("Unnumbered", %{})
      ]

      assert titles(Library.sort_reading_order(books)) == ["#1", "#2", "#3", "Unnumbered"]
    end
  end

  test "get_adjacent_books walks volume-only series" do
    {:ok, admin} =
      Accounts.create_user(%{email: "admin@example.com", username: "admin", password: "password1234", role: :admin})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})
    series = Repo.insert!(Series.changeset(%Series{}, %{name: "Trades", library_id: lib.id}))

    [v1, v2, v3] =
      for v <- [1, 2, 3] do
        {:ok, book} =
          Library.create_book(%{library_id: lib.id, type: "issue", series_id: series.id, title: "Vol #{v}", volume: v})

        book
      end

    access = Access.for_user(admin)
    ids = fn {prev, next} -> {prev && prev.id, next && next.id} end

    assert ids.(Library.get_adjacent_books(access, v1)) == {nil, v2.id}
    assert ids.(Library.get_adjacent_books(access, v2)) == {v1.id, v3.id}
    assert ids.(Library.get_adjacent_books(access, v3)) == {v2.id, nil}
  end
end
