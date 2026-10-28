# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreatorApiTest do
  use StashixWeb.ConnCase, async: false

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.{BookCredit, Creator, Series}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "kid@example.com", username: "kid", password: "password1234"})
    {:ok, token, _refresh} = TokenHelper.generate_tokens(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})

    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, max_age_rating: :teen})

    series = %Series{} |> Series.changeset(%{name: "Night Watch", library_id: lib.id}) |> Repo.insert!()

    book = fn attrs ->
      {:ok, b} =
        Library.create_book(
          Map.merge(%{library_id: lib.id, type: "issue", series_id: series.id, age_rating: :teen}, attrs)
        )

      b
    end

    one = book.(%{title: "Dark Streets", issue_number: 1, year: 1983})
    two = book.(%{title: "Dark Alleys", issue_number: 2, year: 1984})
    hidden = book.(%{title: "Dark Secrets", issue_number: 3, year: 1990, age_rating: :adult})

    walt = Repo.insert!(%Creator{name: "Walt Simonson"})
    louise = Repo.insert!(%Creator{name: "Louise Simonson"})
    credit = fn b, c, role -> Repo.insert!(%BookCredit{book_id: b.id, creator_id: c.id, role: role}) end
    credit.(one, walt, :"Cover Artist")
    credit.(one, walt, :Penciller)
    credit.(one, louise, :Writer)
    credit.(two, walt, :"Cover Artist")
    credit.(hidden, walt, :Writer)

    %{conn: conn, one: one, walt: walt, louise: louise}
  end

  test "books carry their credits with the role and its group", %{conn: conn, one: one, walt: walt, louise: louise} do
    credits = conn |> get(~p"/api/books/#{one.id}") |> json_response(200) |> get_in(["book", "credits"])

    assert credits == [
             %{"creator_id" => louise.id, "name" => "Louise Simonson", "role" => "Writer", "role_group" => "Writer"},
             %{"creator_id" => walt.id, "name" => "Walt Simonson", "role" => "Penciller", "role_group" => "Artist"},
             %{"creator_id" => walt.id, "name" => "Walt Simonson", "role" => "Cover Artist", "role_group" => "Cover"}
           ]

    [result] = conn |> get(~p"/api/search?q=streets") |> json_response(200) |> Map.fetch!("results")
    assert length(result["credits"]) == 3
  end

  test "a creator's work comes grouped by role, leaving out hidden books", %{conn: conn, walt: walt} do
    body = conn |> get(~p"/api/creators/#{walt.id}") |> json_response(200)

    assert body["creator"] == %{"id" => walt.id, "name" => "Walt Simonson"}
    assert body["book_count"] == 2
    assert Enum.map(body["groups"], & &1["role_group"]) == ["Artist", "Cover"]

    [art, covers] = body["groups"]
    assert [%{"name" => "Night Watch", "book_count" => 1, "roles" => ["Penciller"]}] = art["works"]

    assert [%{"name" => "Night Watch", "book_count" => 2, "first_year" => 1983, "last_year" => 1984}] =
             covers["works"]
  end
end
