defmodule StashixWeb.SearchLiveTest do
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
      |> Series.changeset(%{name: "Night Watch", library_id: lib.id, start_year: 1995})
      |> Repo.insert!()

    book = fn attrs ->
      {:ok, b} = Library.create_book(Map.merge(%{library_id: lib.id, type: "issue"}, attrs))
      b
    end

    streets = book.(%{title: "Dark Streets", year: 1995, age_rating: :teen, series_id: series.id, issue_number: 1})
    alleys = book.(%{title: "Dark Alleys", year: 2010, age_rating: :mature, series_id: series.id, issue_number: 2})
    book.(%{title: "Sunny Days", year: 2001, age_rating: :everyone, type: "standalone"})

    moore = Repo.insert!(%Creator{name: "Alan Moore"})
    gibbons = Repo.insert!(%Creator{name: "Dave Gibbons"})
    Repo.insert!(%BookCredit{book_id: streets.id, creator_id: moore.id, role: :Writer})
    Repo.insert!(%BookCredit{book_id: alleys.id, creator_id: moore.id, role: :Artist})
    Repo.insert!(%BookCredit{book_id: alleys.id, creator_id: gibbons.id, role: :Writer})

    %{conn: conn}
  end

  test "filters by release range, age rating and type via URL params", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search")
    assert html =~ "Dark Streets"
    assert html =~ "Sunny Days"
    assert html =~ "Night Watch"

    {:ok, _view, html} = live(conn, ~p"/search?from=2000&to=2005")
    assert html =~ "Sunny Days"
    refute html =~ "Dark Streets"
    refute html =~ "Dark Alleys"
    assert html =~ "Released 2000–2005"

    {:ok, _view, html} = live(conn, ~p"/search?#{%{age: ["mature"]}}")
    assert html =~ "Dark Alleys"
    refute html =~ "Dark Streets"
    refute html =~ "Sunny Days"

    {:ok, _view, html} = live(conn, ~p"/search?type=standalone")
    assert html =~ "Sunny Days"
    refute html =~ "Dark Streets"
    refute html =~ "Night Watch"
  end

  test "free-text search and creator filter match credits", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search?q=moore")
    assert html =~ "Dark Streets"
    assert html =~ "Dark Alleys"
    refute html =~ "Sunny Days"

    {:ok, _view, html} = live(conn, ~p"/search?creator=moore&role=Writer")
    assert html =~ "Dark Streets"
    refute html =~ "Dark Alleys"
    assert html =~ "Creator: moore"
    assert html =~ "Role: Writer"

    # series surface when one of their books matches the creator
    {:ok, _view, html} = live(conn, ~p"/search?creator=gibbons")
    assert html =~ "Night Watch"
    assert html =~ "Dark Alleys"
    refute html =~ "Dark Streets"
  end

  test "form changes patch the URL and chips remove filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search")

    view
    |> form("#search-form", %{"q" => "", "from" => "1990", "to" => "1999", "age" => ["teen"]})
    |> render_change()

    path = assert_patch(view)
    assert path =~ "from=1990"
    assert path =~ "age"

    html = render(view)
    assert html =~ "Dark Streets"
    refute html =~ "Dark Alleys"

    view |> element("button[phx-click=remove_filter][phx-value-key=year]") |> render_click()
    assert_patch(view)

    view |> element("#search-filters button[phx-click=clear_filters]") |> render_click()
    assert_patch(view, ~p"/search")
    assert render(view) =~ "Sunny Days"
  end
end
