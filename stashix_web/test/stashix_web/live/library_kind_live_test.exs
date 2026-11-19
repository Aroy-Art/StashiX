# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.LibraryKindLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{email: "kinds@example.com", username: "kinds", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, comics} = Library.create_library(%{name: "Funnies", root_path: "/tmp/kinds-comics"})
    {:ok, comic} = Library.create_book(%{library_id: comics.id, type: "standalone", title: "Ka-Pow Annual"})

    %{conn: conn, user: user, comics: comics, comic: comic}
  end

  defp add_books_library(_context) do
    {:ok, books} = Library.create_library(%{name: "Novels", root_path: "/tmp/kinds-books", kind: :books})
    {:ok, novel} = Library.create_book(%{library_id: books.id, type: "standalone", title: "Quiet Lighthouse"})
    %{books: books, novel: novel}
  end

  test "no switcher while every library is of one kind", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#kind-switcher")
  end

  describe "with comics and books libraries" do
    setup :add_books_library

    test "the sidebar switcher narrows browse lists, search and the sidebar", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/books")
      assert has_element?(view, "#kind-switcher #kind-all[aria-pressed=true]")
      assert html =~ "Ka-Pow Annual"
      assert html =~ "Quiet Lighthouse"

      assert {:error, {:live_redirect, %{to: "/books"}}} =
               view |> element("#kind-books") |> render_click()

      {:ok, view, html} = live(conn, ~p"/books")
      assert has_element?(view, "#kind-books[aria-pressed=true]")
      assert html =~ "Quiet Lighthouse"
      refute html =~ "Ka-Pow Annual"
      refute has_element?(view, "#sidebar a", "Funnies")
      assert has_element?(view, "#sidebar a", "Novels")

      {:ok, _view, html} = live(conn, ~p"/search?q=a")
      refute html =~ "Ka-Pow Annual"

      {:ok, view, _html} = live(conn, ~p"/")
      html = view |> element("#navbar-search-input") |> render_keyup(%{"value" => "Ka-Pow"})
      refute html =~ "Ka-Pow Annual"
    end

    test "a book of the other kind still opens from a link", %{conn: conn, user: user, comic: comic} do
      {:ok, _} = Accounts.update_ui_settings(user, %{"library_kind" => "books"})

      {:ok, _view, html} = live_canonical(conn, ~p"/book/#{comic.id}")
      assert html =~ "Ka-Pow Annual"
    end

    test "the switcher can sit in the top bar instead", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert has_element?(view, "#sidebar #kind-switcher")

      view |> form("#ui-settings-kind-switcher", %{"kind_switcher" => "top"}) |> render_change()

      assert has_element?(view, "header #kind-switcher")
      refute has_element?(view, "#sidebar #kind-switcher")
    end
  end

  test "a kind with no library the user can read shows everything", %{conn: conn, user: user} do
    {:ok, _} = Accounts.update_ui_settings(user, %{"library_kind" => "books"})

    {:ok, _view, html} = live(conn, ~p"/books")
    assert html =~ "Ka-Pow Annual"
  end

  test "admins pick a library's kind when adding it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    view |> element("button", "Add Library") |> render_click()

    # The kind menu fills a hidden input, so the values go in directly.
    view
    |> element("form[phx-submit=create_library]")
    |> render_submit(%{"name" => "Shelf", "root_path" => "/tmp/kinds-shelf", "kind" => "books"})

    assert Enum.find(Library.list_libraries(%{role: :admin}), &(&1.name == "Shelf")).kind == :books
  end
end
