# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.AnnotationControllerTest do
  use StashixWeb.ConnCase, async: false

  alias Stashix.{Accounts, Annotations, Library}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.Access

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "x@example.com", username: "exporter", password: "password1234"})
    {:ok, other} = Accounts.create_user(%{email: "y@example.com", username: "someone", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})
    {:ok, lib} = Library.create_library(%{name: "Books", root_path: "/tmp/annot"})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
    {:ok, book} = Library.create_book(%{title: "Moby: Dick?", library_id: lib.id})

    locator = %{"type" => "epub", "cfi" => "epubcfi(/6/4!/4/2,/1:0,/1:4)"}

    {:ok, _} =
      Annotations.create(Access.all(), user.id, book, %{
        "kind" => "highlight",
        "color" => "yellow",
        "locator" => locator,
        "text" => "Call",
        "note" => "mine"
      })

    {:ok, _} =
      Annotations.create(Access.all(), other.id, book, %{
        "kind" => "highlight",
        "color" => "yellow",
        "locator" => locator,
        "text" => "theirs"
      })

    %{conn: conn, book: book, other: other}
  end

  test "Markdown export has only the user's own", %{conn: conn, book: book} do
    conn = get(conn, ~p"/api/books/#{book.id}/annotations/export")
    body = response(conn, 200)
    assert body =~ "> Call\n\nmine"
    refute body =~ "theirs"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(filename="Moby Dick annotations.md")
  end

  test "JSON export", %{conn: conn, book: book} do
    assert %{"book" => %{"title" => "Moby: Dick?"}, "annotations" => [%{"text" => "Call", "note" => "mine"}]} =
             conn |> get(~p"/api/books/#{book.id}/annotations/export?format=json") |> json_response(200)
  end

  test "another user's preview is not found", %{conn: conn, book: book, other: other} do
    [theirs] = Annotations.list(other.id, book.id)
    assert conn |> get(~p"/api/annotations/#{theirs.id}/preview") |> json_response(404)
    assert conn |> get(~p"/api/annotations/not-a-uuid/preview") |> json_response(404)
  end
end
