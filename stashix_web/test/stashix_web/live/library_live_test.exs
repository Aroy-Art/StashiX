# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.LibraryLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{email: "lib@example.com", username: "lib", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})
    add_books(lib, 1..50)

    %{conn: conn, lib: lib}
  end

  defp add_books(lib, range) do
    for n <- range do
      {:ok, book} =
        Library.create_book(%{
          library_id: lib.id,
          type: "standalone",
          title: "Book #{String.pad_leading("#{n}", 3, "0")}"
        })

      book
    end
  end

  test "a scan refresh keeps the current page and updates the totals", %{conn: conn, lib: lib} do
    path = ~p"/library/#{lib.id}/books?#{%{page: 2, sort: "title_asc"}}"
    {:ok, view, html} = live(conn, path)
    assert html =~ "page 2 of 2"

    for book <- add_books(lib, 51..97), do: send(view.pid, {:book_added, book})
    send(view.pid, :refresh_after_scan)

    assert_patch(view, path)
    html = render(view)
    assert html =~ ~r/97<\/span>\s*books/
    assert html =~ "page 2 of 3"
  end

  test "a finished scan refreshes the totals", %{conn: conn, lib: lib} do
    {:ok, view, _html} = live(conn, ~p"/library/#{lib.id}/books")

    add_books(lib, 51..52)
    send(view.pid, {:scan_progress, %{library_id: lib.id, scanned: 2, total: 2, done: true}})
    send(view.pid, :refresh_after_scan)

    assert render(view) =~ ~r/52<\/span>\s*books/
  end
end
