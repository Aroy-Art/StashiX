# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.ProgressApiTest do
  use StashixWeb.ConnCase, async: true

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "api@example.com", username: "apiprogress", password: "password1234"})
    {:ok, token, _refresh} = TokenHelper.generate_tokens(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    {:ok, lib} = Library.create_library(%{name: "Books", root_path: "/tmp/progress-api"})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
    {:ok, book} = Library.create_book(%{title: "Novel", library_id: lib.id, page_count: 21})

    %{conn: conn, book: book}
  end

  test "an unopened book reads as the start", %{conn: conn, book: book} do
    assert %{"page" => 0, "progression" => +0.0, "locator" => nil} =
             conn |> get(~p"/api/books/#{book.id}/progress") |> json_response(200)
  end

  test "saves the page, the locator and the progression", %{conn: conn, book: book} do
    locator = %{"type" => "epub", "cfi" => "epubcfi(/6/4!/4/2/1:0)", "href" => "ch1.xhtml"}

    assert %{"status" => "ok", "page" => 7, "progression" => 0.3} =
             conn
             |> put(~p"/api/books/#{book.id}/progress", %{page: 7, progression: 0.3, locator: locator})
             |> json_response(200)

    assert %{"page" => 7, "progression" => 0.3, "locator" => saved} =
             conn |> get(~p"/api/books/#{book.id}/progress") |> json_response(200)

    assert saved == Map.put(locator, "progression", 0.3)
  end

  test "a page alone still works", %{conn: conn, book: book} do
    assert %{"page" => 10, "progression" => 0.5, "locator" => nil} =
             conn |> put(~p"/api/books/#{book.id}/progress", %{page: 10}) |> json_response(200)
  end
end
