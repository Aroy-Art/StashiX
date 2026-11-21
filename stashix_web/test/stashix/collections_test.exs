# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.CollectionsTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Accounts, Collections, Library, Repo}
  alias Stashix.Library.{Access, Book, Series}

  setup do
    {:ok, owner} = Accounts.create_user(%{email: "own@example.com", username: "owner", password: "password1234"})
    {:ok, other} = Accounts.create_user(%{email: "oth@example.com", username: "other", password: "password1234"})
    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/coll-comics"})
    {:ok, locked} = Library.create_library(%{name: "Locked", root_path: "/tmp/coll-locked"})

    for user <- [owner, other] do
      {:ok, _} =
        Library.set_library_permission(%{
          user_id: user.id,
          library_id: lib.id,
          can_read: true,
          max_age_rating: if(user == other, do: :teen, else: nil)
        })
    end

    {:ok, _} = Library.set_library_permission(%{user_id: owner.id, library_id: locked.id, can_read: true})

    saga = Repo.insert!(%Series{name: "Saga", library_id: lib.id, path: "/tmp/coll-comics/saga"})

    issue = fn n, rating ->
      {:ok, b} =
        Library.create_book(%{
          title: "Saga #{n}",
          issue_number: n,
          library_id: lib.id,
          series_id: saga.id,
          age_rating: rating
        })

      b
    end

    s1 = issue.(1, :teen)
    s2 = issue.(2, :adult)
    s3 = issue.(3, :teen)
    {:ok, dune} = Library.create_book(%{title: "Dune", year: 1965, library_id: lib.id, type: "standalone"})
    {:ok, secret} = Library.create_book(%{title: "Behind", library_id: locked.id, type: "standalone"})

    %{
      owner: owner,
      other: other,
      owner_access: Access.for_user(owner),
      other_access: Access.for_user(other),
      saga: saga,
      s1: s1,
      s2: s2,
      s3: s3,
      dune: dune,
      secret: secret,
      lib: lib
    }
  end

  defp ids({books, _total}), do: Enum.map(books, & &1.id)

  test "names are required and unique per owner, ignoring case", %{owner: owner, other: other} do
    assert {:ok, _} = Collections.create(owner, %{name: " To read "})
    assert {:error, changeset} = Collections.create(owner, %{name: "to READ"})
    assert {"you already have a collection with this name", _} = changeset.errors[:name]
    assert {:error, _} = Collections.create(owner, %{name: ""})
    assert {:ok, _} = Collections.create(other, %{name: "To read"})
  end

  test "only the owner edits", %{owner: owner, other: other, other_access: access, dune: dune} do
    {:ok, c} = Collections.create(owner, %{name: "Mine", shared: true})
    assert {:error, :forbidden} = Collections.update(other, c, %{name: "Theirs"})
    assert {:error, :forbidden} = Collections.add(other, access, c, {:book, dune.id})
    assert {:error, :forbidden} = Collections.delete(other, c)
    assert {:ok, _} = Collections.update(owner, c, %{name: "Still mine"})
  end

  test "a series stands for its books, now and later, without duplicates", ctx do
    %{owner: owner, owner_access: access, saga: saga, s1: s1, s2: s2, s3: s3, dune: dune} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Reading order"})

    {:ok, _} = Collections.add(owner, access, c, {:book, s3.id})
    {:ok, _} = Collections.add(owner, access, c, {:series, saga.id})
    {:ok, _} = Collections.add(owner, access, c, {:book, dune.id})
    assert {:ok, :exists} = Collections.add(owner, access, c, {:book, dune.id})

    # #3 stays at its own, earlier place; the series brings the rest in order.
    assert ids(Collections.books(access, c)) == [s3.id, s1.id, s2.id, dune.id]

    {:ok, s4} = Library.create_book(%{title: "Saga 4", issue_number: 4, library_id: ctx.lib.id, series_id: saga.id})
    assert ids(Collections.books(access, c)) == [s3.id, s1.id, s2.id, s4.id, dune.id]

    assert {[_, _], 5} = Collections.books(access, c, "position", limit: 2)
    assert ids(Collections.books(access, c, "title")) |> hd() == dune.id
  end

  test "viewers see a shared collection limited to what they may read", ctx do
    %{owner: owner, other: other, owner_access: access, other_access: other_access} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Mixed"})
    {:ok, _} = Collections.add(owner, access, c, {:series, ctx.saga.id})
    {:ok, _} = Collections.add(owner, access, c, {:book, ctx.secret.id})

    # Not shared: invisible to others.
    assert {:error, :not_found} = Collections.get(other, other_access, c.id)
    assert Collections.list_for(other, other_access) == []

    {:ok, c} = Collections.update(owner, c, %{shared: true})
    assert {:ok, _} = Collections.get(other, other_access, c.id)
    assert ids(Collections.books(other_access, c)) == [ctx.s1.id, ctx.s3.id]
    assert [%{own?: false, count: 2}] = Collections.list_for(other, other_access)
    assert [%{own?: true, count: 4}] = Collections.list_for(owner, access)

    # Shared but nothing they may read: hidden.
    {:ok, only_secret} = Collections.create(owner, %{name: "Locked away", shared: true})
    {:ok, _} = Collections.add(owner, access, only_secret, {:book, ctx.secret.id})
    assert {:error, :not_found} = Collections.get(other, other_access, only_secret.id)
    assert length(Collections.list_for(other, other_access)) == 1
  end

  test "the owner can't add what they can't read", %{other: other, other_access: access, s2: s2} do
    {:ok, c} = Collections.create(other, %{name: "Teen"})
    assert {:error, :not_found} = Collections.add(other, access, c, {:book, s2.id})
  end

  test "entries move, renumbering when there is no room", ctx do
    %{owner: owner, owner_access: access} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Order"})
    {:ok, a} = Collections.add(owner, access, c, {:book, ctx.s1.id})
    {:ok, b} = Collections.add(owner, access, c, {:book, ctx.s2.id})
    {:ok, d} = Collections.add(owner, access, c, {:book, ctx.dune.id})

    order = fn -> Collections.entries(access, c) |> Enum.map(& &1.id) end

    assert :ok = Collections.move(owner, c, d.id, 0)
    assert order.() == [d.id, a.id, b.id]

    # Squeeze one spot until the gap runs out: order still holds.
    for _ <- 1..12 do
      :ok = Collections.move(owner, c, b.id, 1)
      :ok = Collections.move(owner, c, a.id, 1)
    end

    assert order.() == [d.id, a.id, b.id]
    assert :ok = Collections.move(owner, c, d.id, 99)
    assert order.() == [a.id, b.id, d.id]
  end

  test "entries list what the viewer may see, with books and series loaded", ctx do
    %{owner: owner, owner_access: access, other_access: other_access} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Entries", shared: true})
    {:ok, _} = Collections.add(owner, access, c, {:series, ctx.saga.id})
    {:ok, _} = Collections.add(owner, access, c, {:book, ctx.s2.id})

    assert [%{series: %Series{name: "Saga"}}, %{book: %Book{title: "Saga 2"}}] = Collections.entries(access, c)
    assert [%{series: %Series{}}] = Collections.entries(other_access, c)
  end

  test "which collections hold a book or series", ctx do
    %{owner: owner, owner_access: access} = ctx
    {:ok, by_series} = Collections.create(owner, %{name: "Series"})
    {:ok, by_book} = Collections.create(owner, %{name: "Book"})
    {:ok, _} = Collections.add(owner, access, by_series, {:series, ctx.saga.id})
    {:ok, _} = Collections.add(owner, access, by_book, {:book, ctx.s1.id})

    assert Collections.containing(owner, {:book, ctx.s1.id}) == %{by_series.id => :series, by_book.id => :direct}
    assert Collections.containing(owner, {:series, ctx.saga.id}) == %{by_series.id => :direct}
    assert Collections.containing(owner, {:book, ctx.dune.id}) == %{}
    assert Collections.holding_book(owner, access, ctx.s1.id) |> Enum.map(& &1.name) == ["Book", "Series"]

    :ok = Collections.remove(owner, by_book, {:book, ctx.s1.id})
    assert Collections.containing(owner, {:book, ctx.s1.id}) == %{by_series.id => :series}
  end

  test "removing a book that is there through its series takes the series apart", ctx do
    %{owner: owner, owner_access: access} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Spread"})
    {:ok, _} = Collections.add(owner, access, c, {:book, ctx.dune.id})
    {:ok, _} = Collections.add(owner, access, c, {:series, ctx.saga.id})
    {:ok, _} = Collections.add(owner, access, c, {:book, ctx.secret.id})

    :ok = Collections.remove_book(owner, access, c, ctx.s2.id)

    entries = Collections.entries(access, c)

    assert Enum.map(entries, &(&1.book_id || {:series, &1.series_id})) == [
             ctx.dune.id,
             ctx.s1.id,
             ctx.s3.id,
             ctx.secret.id
           ]

    assert ids(Collections.books(access, c)) == [ctx.dune.id, ctx.s1.id, ctx.s3.id, ctx.secret.id]

    # A book with its own entry just loses it.
    :ok = Collections.remove_book(owner, access, c, ctx.dune.id)
    assert ids(Collections.books(access, c)) == [ctx.s1.id, ctx.s3.id, ctx.secret.id]
  end

  test "deleting a book or series removes its entries", ctx do
    %{owner: owner, owner_access: access} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Gone"})
    {:ok, _} = Collections.add(owner, access, c, {:book, ctx.dune.id})
    Repo.delete!(ctx.dune)
    assert Collections.entries(access, c) == []
  end
end
