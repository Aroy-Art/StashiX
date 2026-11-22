# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionApiTest do
  use StashixWeb.ConnCase, async: true

  alias Stashix.{Accounts, Collections, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{Access, Series}

  setup do
    owner = user("apiowner")
    other = user("apiother")
    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/collection-api"})

    for u <- [owner, other],
        do: {:ok, _} = Library.set_library_permission(%{user_id: u.id, library_id: lib.id, can_read: true})

    saga = Repo.insert!(%Series{name: "Saga", library_id: lib.id, path: "/tmp/collection-api/saga"})
    {:ok, s1} = Library.create_book(%{title: "Saga 1", issue_number: 1, library_id: lib.id, series_id: saga.id})
    {:ok, s2} = Library.create_book(%{title: "Saga 2", issue_number: 2, library_id: lib.id, series_id: saga.id})
    {:ok, dune} = Library.create_book(%{title: "Dune", library_id: lib.id, type: "standalone"})

    %{conn: api(owner), other_conn: api(other), owner: owner, saga: saga, s1: s1, s2: s2, dune: dune}
  end

  defp user(name) do
    {:ok, u} = Accounts.create_user(%{email: "#{name}@example.com", username: name, password: "password1234"})
    u
  end

  defp api(user) do
    {:ok, token, _refresh} = TokenHelper.generate_tokens(user)
    build_conn() |> put_req_header("authorization", "Bearer #{token}") |> put_req_header("accept", "application/json")
  end

  test "a collection is made, filled, read and ordered", ctx do
    %{conn: conn, saga: saga, dune: dune, s1: s1, s2: s2} = ctx

    %{"collection" => %{"id" => id, "own" => true, "book_count" => 0}} =
      conn |> post(~p"/api/collections", %{name: "Space operas"}) |> json_response(201)

    %{"id" => dune_entry, "type" => "book"} =
      conn |> post(~p"/api/collections/#{id}/entries", %{book_id: dune.id}) |> json_response(201)

    %{"type" => "series", "series" => %{"name" => "Saga", "issue_count" => 2}} =
      conn |> post(~p"/api/collections/#{id}/entries", %{series_id: saga.id}) |> json_response(201)

    assert %{"status" => "exists"} =
             conn |> post(~p"/api/collections/#{id}/entries", %{book_id: dune.id}) |> json_response(200)

    assert conn |> post(~p"/api/collections/#{id}/entries", %{}) |> json_response(400)

    %{"collection" => %{"book_count" => 3}, "entries" => [%{"id" => ^dune_entry}, _]} =
      conn |> get(~p"/api/collections/#{id}") |> json_response(200)

    assert conn |> put(~p"/api/collections/#{id}/entries/#{dune_entry}/position", %{index: 1}) |> response(204)

    %{"books" => books, "total" => 3} = conn |> get(~p"/api/collections/#{id}/books") |> json_response(200)
    assert Enum.map(books, & &1["id"]) == [s1.id, s2.id, dune.id]

    %{"books" => [%{"title" => "Dune"}]} =
      conn |> get(~p"/api/collections/#{id}/books?sort=title&limit=1") |> json_response(200)

    assert conn |> delete(~p"/api/collections/#{id}/entries/#{dune_entry}") |> response(204)
    assert %{"book_count" => 2} = conn |> patch(~p"/api/collections/#{id}", %{shared: true}) |> json_response(200)

    assert [%{"name" => "Space operas", "shared" => true}] =
             conn |> get(~p"/api/collections") |> json_response(200) |> Map.fetch!("collections")

    assert conn |> delete(~p"/api/collections/#{id}") |> response(204)
    assert conn |> get(~p"/api/collections/#{id}") |> json_response(404)
  end

  test "the cover is picked and reset through update", %{conn: conn, owner: owner, dune: dune, s1: s1} do
    {:ok, c} = Collections.create(owner, %{name: "Covered"})
    {:ok, _} = Collections.add(owner, Access.for_user(owner), c, {:book, dune.id})

    assert %{"cover_book_id" => nil} = conn |> patch(~p"/api/collections/#{c.id}", %{}) |> json_response(200)

    assert %{"cover_book_id" => id} =
             conn |> patch(~p"/api/collections/#{c.id}", %{cover_book_id: dune.id}) |> json_response(200)

    assert id == dune.id

    # A book outside the collection can be picked but only shows when in it.
    assert %{"cover_book_id" => nil} =
             conn |> patch(~p"/api/collections/#{c.id}", %{cover_book_id: s1.id}) |> json_response(200)

    assert conn |> patch(~p"/api/collections/#{c.id}", %{cover_book_id: "nope"}) |> json_response(422)

    assert %{"cover_book_id" => nil} =
             conn |> patch(~p"/api/collections/#{c.id}", %{cover_book_id: nil}) |> json_response(200)
  end

  test "names must be there and unique", %{conn: conn} do
    assert %{"errors" => %{"name" => _}} = conn |> post(~p"/api/collections", %{name: ""}) |> json_response(422)
    conn |> post(~p"/api/collections", %{name: "Twice"}) |> json_response(201)

    assert %{"errors" => %{"name" => [msg]}} =
             conn |> post(~p"/api/collections", %{name: "twice"}) |> json_response(422)

    assert msg =~ "already"
  end

  test "others read shared collections but can't change them", ctx do
    %{other_conn: other, owner: owner, dune: dune} = ctx
    {:ok, c} = Collections.create(owner, %{name: "Private"})
    {:ok, entry} = Collections.add(owner, Access.for_user(owner), c, {:book, dune.id})

    assert other |> get(~p"/api/collections/#{c.id}") |> json_response(404)

    {:ok, _} = Collections.update(owner, c, %{shared: true})

    assert %{"collection" => %{"own" => false, "owner" => "apiowner"}} =
             other |> get(~p"/api/collections/#{c.id}") |> json_response(200)

    assert other |> patch(~p"/api/collections/#{c.id}", %{name: "Mine now"}) |> json_response(403)
    assert other |> post(~p"/api/collections/#{c.id}/entries", %{book_id: dune.id}) |> json_response(403)
    assert other |> put(~p"/api/collections/#{c.id}/entries/#{entry.id}/position", %{index: 0}) |> json_response(403)
    assert other |> delete(~p"/api/collections/#{c.id}/entries/#{entry.id}") |> json_response(403)
    assert other |> delete(~p"/api/collections/#{c.id}") |> json_response(403)
  end

  test "needs a token", %{} do
    assert build_conn() |> get(~p"/api/collections") |> json_response(401)
  end
end
