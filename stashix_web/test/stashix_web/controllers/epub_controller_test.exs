# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.EpubControllerTest do
  use StashixWeb.ConnCase, async: false

  import Stashix.EpubFixtures

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.BookFile

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "e@example.com", username: "epubber", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})

    book = fn title, kind ->
      {:ok, b} = Library.create_book(%{title: title, library_id: lib.id})
      path = make_epub(Path.join(tmp, "#{title}.epub"), [{:text, "<script>alert(1)</script>Call me Ishmael."}])
      Repo.insert!(%BookFile{book_id: b.id, path: path, format: :epub, file_size: 1, content_kind: kind})
      b
    end

    %{conn: conn, text: book.("Novel", :text), manga: book.("Manga", :images)}
  end

  test "lists entries with their sizes", %{conn: conn, text: book} do
    assert %{"entries" => %{"OEBPS/content.opf" => size}} =
             conn |> get(~p"/api/books/#{book.id}/epub") |> json_response(200)

    assert size > 0
  end

  test "serves one entry, typed from the package, locked down", %{conn: conn, text: book} do
    conn = get(conn, "/api/books/#{book.id}/epub/OEBPS/text/ch1.xhtml")
    assert conn.status == 200
    assert conn.resp_body =~ "Call me Ishmael."
    assert get_resp_header(conn, "content-type") == ["application/xhtml+xml"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "sandbox"
    assert csp =~ "default-src 'none'"
  end

  test "names outside the zip are not found", %{conn: conn, text: book} do
    assert get(conn, "/api/books/#{book.id}/epub/OEBPS/missing.xhtml").status == 404
    assert get(conn, "/api/books/#{book.id}/epub/../../etc/passwd").status == 404
  end

  test "books that open as pages are forbidden", %{conn: conn, manga: book} do
    assert get(conn, ~p"/api/books/#{book.id}/epub").status == 403
    assert get(conn, "/api/books/#{book.id}/epub/mimetype").status == 403
  end
end
