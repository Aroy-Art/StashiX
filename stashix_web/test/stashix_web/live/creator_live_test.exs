# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreatorLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.{BookCredit, Creator, Series}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "admin@example.com", username: "admin", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})

    series =
      %Series{}
      |> Series.changeset(%{name: "Night Watch", library_id: lib.id})
      |> Repo.insert!()

    book = fn attrs ->
      {:ok, b} = Library.create_book(Map.merge(%{library_id: lib.id, type: "issue", series_id: series.id}, attrs))
      b
    end

    one = book.(%{title: "Dark Streets", issue_number: 1, year: 1983})
    two = book.(%{title: "Dark Alleys", issue_number: 2, year: 1984})
    three = book.(%{title: "Dark Roofs", issue_number: 3, year: 1987})
    sunny = book.(%{title: "Sunny Days", type: "standalone", series_id: nil, year: 2001})

    walt = Repo.insert!(%Creator{name: "Walt Simonson"})

    credit = fn b, role -> Repo.insert!(%BookCredit{book_id: b.id, creator_id: walt.id, role: role}) end
    credit.(one, :Writer)
    credit.(two, :Writer)
    credit.(one, :Penciller)
    credit.(one, :Inker)
    for b <- [one, two, three, sunny], do: credit.(b, :"Cover Artist")

    %{conn: conn, walt: walt}
  end

  test "groups a creator's work by role, opening on writing over covers", %{conn: conn, walt: walt} do
    {:ok, view, html} = live(conn, ~p"/creator/#{walt.id}")

    assert html =~ "Walt Simonson"
    assert html =~ "1983–2001"
    assert has_element?(view, ~s(nav[aria-label="Roles"] a), "Written")
    assert has_element?(view, ~s(nav[aria-label="Roles"] a), "Art")
    assert has_element?(view, ~s(nav[aria-label="Roles"] a), "Covers")
    refute has_element?(view, ~s(nav[aria-label="Roles"] a), "Colors")

    # Written is the default even though Covers has more books
    assert has_element?(view, ~s(nav[aria-label="Roles"] a[aria-current="page"]), "Written")
    assert html =~ "2 issues"
    assert html =~ "1983–1984"
    refute html =~ "Sunny Days"

    html = render_patch(view, ~p"/creator/#{walt.id}?role=art")
    assert html =~ "1 issue"
    assert html =~ "Inker, Penciller"

    html = render_patch(view, ~p"/creator/#{walt.id}?role=covers")
    assert html =~ "3 issues"
    assert html =~ "Sunny Days"
    refute html =~ "Cover Artist"
  end

  test "credit links on a book lead to the creator page", %{conn: conn, walt: walt} do
    book = Repo.get_by!(Stashix.Library.Book, title: "Dark Streets")

    {:ok, view, _html} = live(conn, ~p"/book/#{book.id}")
    assert has_element?(view, ~s(a[href="/creator/#{walt.id}"]))
  end
end
