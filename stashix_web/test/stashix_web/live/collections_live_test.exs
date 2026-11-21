# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionsLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Collections, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{Access, Series}

  setup %{conn: conn} do
    owner = user("owner")
    other = user("other")
    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/collections-live"})

    for u <- [owner, other],
        do: {:ok, _} = Library.set_library_permission(%{user_id: u.id, library_id: lib.id, can_read: true})

    saga = Repo.insert!(%Series{name: "Saga", library_id: lib.id, path: "/tmp/collections-live/saga"})

    {:ok, s1} =
      Library.create_book(%{title: "Chapter One", issue_number: 1, library_id: lib.id, series_id: saga.id})

    {:ok, dune} = Library.create_book(%{title: "Dune", year: 1965, library_id: lib.id, type: "standalone"})
    {:ok, c} = Collections.create(owner, %{name: "Space operas", description: "Big ships."})
    {:ok, e_dune} = Collections.add(owner, Access.for_user(owner), c, {:book, dune.id})
    {:ok, e_saga} = Collections.add(owner, Access.for_user(owner), c, {:series, saga.id})

    %{
      conn: sign_in(conn, owner),
      other_conn: sign_in(build_conn(), other),
      owner: owner,
      other: other,
      c: c,
      dune: dune,
      s1: s1,
      e_dune: e_dune,
      e_saga: e_saga
    }
  end

  defp user(name) do
    {:ok, u} = Accounts.create_user(%{email: "#{name}@example.com", username: name, password: "password1234"})
    u
  end

  defp sign_in(conn, user) do
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})
  end

  test "the nav leads to collections, listed with their counts", %{conn: conn, c: c} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s|#sidebar a[href="/collections"]|)

    {:ok, view, _html} = live(conn, ~p"/collections")
    assert has_element?(view, "#own-collections #collection-#{c.id}", "Space operas")
    refute has_element?(view, "#shared-collections")
  end

  test "a UI setting lists your collections in the sidebar", %{conn: conn, c: c} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    refute has_element?(view, "#sidebar-collections")

    view |> form("#ui-settings-collections-sidebar", %{"collections_sidebar" => "on"}) |> render_change()
    assert has_element?(view, ~s|#sidebar-collections a[href="/collection/#{c.id}"]|, "Space operas")

    {:ok, view, _html} = live(conn, ~p"/collection/#{c.id}")
    assert has_element?(view, ~s|#sidebar-collections a[aria-current="page"]|, "Space operas")
  end

  test "search finds collections by name", %{conn: conn, other_conn: other_conn, owner: owner, c: c} do
    {:ok, view, _html} = live(conn, ~p"/search?q=opera")
    assert has_element?(view, ~s|#search-collections a[href="/collection/#{c.id}"]|, "Space operas")
    refute render(view) =~ "Nothing in the long box"

    {:ok, view, _html} = live(conn, ~p"/search?q=dune")
    refute has_element?(view, "#search-collections")

    # Others find it once it is shared.
    {:ok, view, _html} = live(other_conn, ~p"/search?q=opera")
    refute has_element?(view, "#search-collections")
    {:ok, _} = Collections.update(owner, c, %{shared: true})
    {:ok, view, _html} = live(other_conn, ~p"/search?q=opera")
    assert has_element?(view, "#search-collections", "Space operas")
  end

  test "the home page shows your collections unless turned off", %{conn: conn, owner: owner, c: c} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s|#home-collections #home-collection-#{c.id}|, "Space operas")

    {:ok, _} = Accounts.update_ui_settings(owner, %{"home_collections" => "off"})
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "#home-collections")
  end

  test "a new collection is made from the dialog", %{conn: conn, owner: owner} do
    {:ok, view, _html} = live(conn, ~p"/collections")
    view |> element("#new-collection") |> render_click()

    assert view |> form("#new-collection-form", %{collection: %{name: "Space operas"}}) |> render_submit() =~
             "already have a collection"

    view |> form("#new-collection-form", %{collection: %{name: "Book club"}}) |> render_submit()
    [created] = owner |> Collections.own() |> Enum.filter(&(&1.name == "Book club"))
    assert_redirect(view, ~p"/collection/#{created.id}")
  end

  test "a collection shows its entries in order, or its books sorted", ctx do
    %{conn: conn, c: c, e_dune: e_dune, e_saga: e_saga} = ctx
    {:ok, view, html} = live(conn, ~p"/collection/#{c.id}")

    assert html =~ "Big ships."
    assert has_element?(view, "#entry-#{e_dune.id}", "Dune")
    assert has_element?(view, "#entry-#{e_saga.id}", "Saga")
    assert has_element?(view, "#read-next", "Dune")

    view |> element("#collection-sort") |> render_change(%{"value" => "title"})
    assert_patch(view, ~p"/collection/#{c.id}?sort=title")
    assert has_element?(view, "#collection-books", "Chapter One")
    refute has_element?(view, "#collection-entries")
  end

  test "the owner moves, removes, edits, shares and deletes", ctx do
    %{conn: conn, c: c, e_dune: e_dune, e_saga: e_saga, owner: owner} = ctx
    {:ok, view, _html} = live(conn, ~p"/collection/#{c.id}")

    view |> element("#entry-menu-#{e_saga.id} button", "Move to top") |> render_click()
    order = Collections.entries(Access.for_user(owner), c) |> Enum.map(& &1.id)
    assert order == [e_saga.id, e_dune.id]

    view |> element("#entry-menu-#{e_dune.id} button", "Remove from collection") |> render_click()
    refute has_element?(view, "#entry-#{e_dune.id}")

    view |> element("#collection-menu button", "Edit name and description") |> render_click()
    view |> form("#edit-collection-form", %{collection: %{name: "Sagas", description: ""}}) |> render_submit()
    assert render(view) =~ "Sagas"
    refute has_element?(view, "#collection-description")

    view |> element("#collection-menu button", "Share with everyone") |> render_click()
    assert render(view) =~ "yours · shared"

    view |> element("#collection-menu button", "Delete collection") |> render_click()
    assert_redirect(view, ~p"/collections")
    assert Collections.own(owner) == []
  end

  test "dragging a card reorders, for the owner only", ctx do
    %{conn: conn, other_conn: other_conn, owner: owner, c: c, e_dune: e_dune, e_saga: e_saga} = ctx
    {:ok, view, _html} = live(conn, ~p"/collection/#{c.id}")
    assert has_element?(view, ~s|#collection-entries[phx-hook="SortableList"][data-enabled="true"]|)

    render_hook(view, "reorder", %{"id" => e_saga.id, "index" => 0})
    assert Collections.entries(Access.for_user(owner), c) |> Enum.map(& &1.id) == [e_saga.id, e_dune.id]

    {:ok, _} = Collections.update(owner, c, %{shared: true})
    {:ok, view, _html} = live(other_conn, ~p"/collection/#{c.id}")
    assert has_element?(view, ~s|#collection-entries[data-enabled="false"]|)
    render_hook(view, "reorder", %{"id" => e_dune.id, "index" => 0})
    assert Collections.entries(Access.for_user(owner), c) |> Enum.map(& &1.id) == [e_saga.id, e_dune.id]
  end

  test "others see it only when shared, read-only", %{other_conn: conn, owner: owner, c: c} do
    assert {:error, {:live_redirect, %{to: "/collections"}}} = live(conn, ~p"/collection/#{c.id}")

    {:ok, _} = Collections.update(owner, c, %{shared: true})
    {:ok, view, html} = live(conn, ~p"/collection/#{c.id}")
    assert html =~ "shared by owner"
    refute has_element?(view, "#collection-menu")
    refute has_element?(view, "[id^=entry-menu-]")

    {:ok, view, _html} = live(conn, ~p"/collections")
    assert has_element?(view, "#shared-collections #collection-#{c.id}", "by owner")
  end

  describe "the Collection button" do
    test "ticks add and remove a book, and the book page lists its collections", ctx do
      %{conn: conn, owner: owner, c: c, s1: s1} = ctx
      {:ok, other} = Collections.create(owner, %{name: "Book club"})
      {:ok, view, _html} = live_canonical(conn, ~p"/book/#{s1.id}")

      # In "Space operas" through Saga; not in "Book club".
      assert has_element?(view, ~s|#collection-picker-#{c.id}[aria-checked="false"]|, "via series")
      assert has_element?(view, "#book-collections", "Space operas")

      view |> element("#collection-picker-#{other.id}") |> render_click()
      assert has_element?(view, ~s|#collection-picker-#{other.id}[aria-checked="true"]|)
      assert has_element?(view, "#book-collections", "Book club")
      assert Collections.containing(owner, {:book, s1.id})[other.id] == :direct

      view |> element("#collection-picker-#{other.id}") |> render_click()
      refute has_element?(view, "#book-collections", "Book club")
    end

    test "a new collection is made with the item in it", %{conn: conn, owner: owner, dune: dune} do
      {:ok, view, _html} = live_canonical(conn, ~p"/book/#{dune.id}")
      view |> element("#collection-picker-menu button", "New collection…") |> render_click()
      view |> form("#collection-picker-new-form", %{collection: %{name: "Classics"}}) |> render_submit()

      [classics] = owner |> Collections.own() |> Enum.filter(&(&1.name == "Classics"))
      assert Collections.containing(owner, {:book, dune.id})[classics.id] == :direct
      assert has_element?(view, "#book-collections", "Classics")
      refute has_element?(view, "#collection-picker-new")
    end

    test "a whole series goes in from its page", %{conn: conn, owner: owner} do
      {:ok, fresh} = Collections.create(owner, %{name: "Ongoing"})
      saga = Repo.get_by!(Series, name: "Saga")
      {:ok, view, _html} = live_canonical(conn, ~p"/series/#{saga.id}")

      view |> element("#collection-picker-#{fresh.id}") |> render_click()
      assert Collections.containing(owner, {:series, saga.id})[fresh.id] == :direct
    end
  end
end
