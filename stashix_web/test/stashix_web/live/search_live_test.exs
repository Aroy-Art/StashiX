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

    %{conn: conn, moore: moore, gibbons: gibbons}
  end

  test "filters by release range, age rating and type via URL params", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search")
    assert html =~ "Dark Streets"
    assert html =~ "Sunny Days"
    assert html =~ "Night Watch"

    # histogram covers the library's years
    assert html =~ "1995: 1 book"
    assert html =~ "2003: 0 books"

    {:ok, _view, html} = live(conn, ~p"/search?from=2001&to=2001")
    assert html =~ "Sunny Days"
    refute html =~ "Dark Streets"
    refute html =~ "Dark Alleys"
    assert html =~ ~r/Released 2001\s*</

    # years with no books are ignored, as is a bound at the library's edge
    {:ok, _view, html} = live(conn, ~p"/search?from=2000&to=2010")
    assert html =~ "Dark Streets"
    refute html =~ "Released"

    {:ok, _view, html} = live(conn, ~p"/search?#{%{age: ["mature"]}}")
    assert html =~ "Dark Alleys"
    refute html =~ "Dark Streets"
    refute html =~ "Sunny Days"

    {:ok, _view, html} = live(conn, ~p"/search?type=standalone")
    assert html =~ "Sunny Days"
    refute html =~ "Dark Streets"
    refute html =~ "Night Watch"
  end

  test "free-text search and creator filter match credits", %{conn: conn, moore: moore, gibbons: gibbons} do
    {:ok, _view, html} = live(conn, ~p"/search?q=moore")
    assert html =~ "Dark Streets"
    assert html =~ "Dark Alleys"
    refute html =~ "Sunny Days"

    {:ok, _view, html} = live(conn, ~p"/search?creator=#{moore.id}&role=Writer")
    assert html =~ "Dark Streets"
    refute html =~ "Dark Alleys"
    assert html =~ "Creator: Alan Moore"
    assert html =~ "Role: Writer"

    # series surface when one of their books matches the creator
    {:ok, _view, html} = live(conn, ~p"/search?creator=#{gibbons.id}")
    assert html =~ "Night Watch"
    assert html =~ "Dark Alleys"
    refute html =~ "Dark Streets"

    # a malformed id is ignored rather than crashing
    {:ok, _view, html} = live(conn, ~p"/search?creator=not-a-uuid")
    assert html =~ "Sunny Days"
  end

  test "multiple creators match all (default) or any", %{conn: conn, moore: moore, gibbons: gibbons} do
    both = [moore.id, gibbons.id]

    # all: only the book both are credited on
    {:ok, _view, html} = live(conn, ~p"/search?#{%{creator: both}}")
    assert html =~ "Dark Alleys"
    refute html =~ "Dark Streets"
    assert html =~ "Creator: Alan Moore"
    assert html =~ "and Dave Gibbons"
    assert html =~ "All of them"

    {:ok, _view, html} = live(conn, ~p"/search?#{%{creator: both, creator_match: "any"}}")
    assert html =~ "Dark Alleys"
    assert html =~ "Dark Streets"
    refute html =~ "Sunny Days"
    assert html =~ "or Dave Gibbons"

    # role applies to each creator: Moore is only the artist on Dark Alleys
    {:ok, _view, html} = live(conn, ~p"/search?#{%{creator: both, role: "Writer"}}")
    refute html =~ "Dark Alleys"
    refute html =~ "Dark Streets"
  end

  test "creator picker adds creators one by one", %{conn: conn, moore: moore, gibbons: gibbons} do
    {:ok, view, _html} = live(conn, ~p"/search")

    html = type_creator(view, "moo")
    assert html =~ "Alan Moore"
    refute html =~ "Dave Gibbons"
    # typing alone doesn't touch the URL
    refute_patched(view)

    view |> element("[phx-click=select_creator]", "Alan Moore") |> render_click()
    assert_patch(view, ~p"/search?#{%{creator: [moore.id]}}")
    assert render(view) =~ "Creator: Alan Moore"
    refute render(view) =~ "Sunny Days"

    # the search box stays for adding more; already-picked creators aren't suggested
    assert has_element?(view, "#creator-search")
    refute type_creator(view, "moo") =~ "phx-value-id=\"#{moore.id}\""

    type_creator(view, "gib")
    view |> element("[phx-click=select_creator]", "Dave Gibbons") |> render_click()
    assert_patch(view, ~p"/search?#{%{creator: [moore.id, gibbons.id]}}")

    # changing another filter keeps the selected creators
    view |> form("#search-form", %{"creator_match" => "any"}) |> render_change()
    path = assert_patch(view)
    assert path =~ "creator_match=any"
    assert path =~ moore.id and path =~ gibbons.id

    view |> element("button[aria-label='Remove Alan Moore']") |> render_click()
    path = assert_patch(view)
    refute path =~ moore.id
    assert path =~ gibbons.id
    # match mode is meaningless with one creator and is dropped
    refute path =~ "creator_match"
  end

  test "navbar search box is synced with the page query", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/search?q=sunny&from=2001")
    assert html =~ ~r/id="navbar-search-input"[^>]*value="sunny"/

    # typing in the navbar updates results in place (keeping filters), no dropdown
    view |> element("#navbar-search-input") |> render_keyup(%{"value" => "dark"})
    path = assert_patch(view)
    assert path =~ "q=dark"
    assert path =~ "from=2001"
    html = render(view)
    refute html =~ "See all results for"
    assert html =~ ~r/name="q"[^>]*value="dark"/

    # Enter in the navbar stays on the page instead of a full GET
    view |> element("#navbar-search-input") |> render_keyup(%{"value" => "dark"})
    refute_patched(view)

    view |> form("form[phx-submit=navbar_submit]", %{"q" => "streets"}) |> render_submit()
    assert assert_patch(view) =~ "q=streets"

    # the clear button empties the query but keeps filters
    view |> element("button[aria-label='Clear search']") |> render_click()
    path = assert_patch(view)
    refute path =~ "q="
    assert path =~ "from=2001"
    refute has_element?(view, "button[aria-label='Clear search']")

    # page box -> navbar box
    view |> form("#search-form", %{"q" => "alleys"}) |> render_change()
    assert_patch(view)
    assert render(view) =~ ~r/id="navbar-search-input"[^>]*value="alleys"/
  end

  defp type_creator(view, text) do
    view
    |> form("#search-form", %{"creator_search" => text})
    |> render_change(%{"_target" => ["creator_search"]})
  end

  test "form changes patch the URL and chips remove filters", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search")

    view |> form("#search-form", %{"age" => ["teen", "mature"]}) |> render_change()
    assert assert_patch(view) =~ "age"

    # slider release: from at the first year is no bound
    view |> element("#year-range") |> render_hook("set_years", %{"from" => "1995", "to" => "2001"})
    path = assert_patch(view)
    assert path =~ "to=2001"
    refute path =~ "from="
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

  test "genre, tag, character, team and location filters match books by name", %{conn: conn} do
    alias Stashix.Library.{Book, BookCharacter, BookGenre, BookLocation, BookTag, BookTeam}

    streets = Repo.get_by!(Book, title: "Dark Streets")
    alleys = Repo.get_by!(Book, title: "Dark Alleys")
    Repo.insert!(%BookGenre{book_id: alleys.id, name: "Mystery"})
    Repo.insert!(%BookTag{book_id: streets.id, name: "Noir"})
    Repo.insert!(%BookCharacter{book_id: streets.id, name: "Rorschach & Co"})
    Repo.insert!(%BookTeam{book_id: alleys.id, name: "Minutemen"})
    Repo.insert!(%BookLocation{book_id: alleys.id, name: "New York"})

    for {param, value, hit, miss} <- [
          {"genre", "Mystery", "Dark Alleys", "Dark Streets"},
          {"tag", "Noir", "Dark Streets", "Dark Alleys"},
          {"character", "Rorschach & Co", "Dark Streets", "Dark Alleys"},
          {"team", "Minutemen", "Dark Alleys", "Dark Streets"},
          {"location", "New York", "Dark Alleys", "Dark Streets"}
        ] do
      {:ok, _view, html} = live(conn, ~p"/search?#{%{param => value, "type" => "issue"}}")
      assert html =~ hit
      refute html =~ miss
      refute html =~ "Sunny Days"
    end

    # the series tab keeps series containing a matching book
    {:ok, _view, html} = live(conn, ~p"/search?tag=Noir&type=series")
    assert html =~ "Night Watch"

    {:ok, _view, html} = live(conn, ~p"/search?tag=Nope&type=series")
    refute html =~ "Night Watch"

    # several names in one facet must all be on the book
    Repo.insert!(%BookTag{book_id: streets.id, name: "Crime"})
    Repo.insert!(%BookTag{book_id: alleys.id, name: "Crime"})

    {:ok, _view, html} = live(conn, ~p"/search?#{%{tag: ["Crime", "Noir"], type: "issue"}}")
    assert html =~ "Dark Streets"
    refute html =~ "Dark Alleys"

    # the picker suggests names and adds the chosen one to the URL
    {:ok, view, _html} = live(conn, ~p"/search")

    html =
      view
      |> form("#search-form")
      |> render_change(%{"_target" => ["team_search"], "team_search" => "minu"})

    assert html =~ "Minutemen"
    view |> element("#team-options button", "Minutemen") |> render_click()
    assert_patch(view, ~p"/search?#{%{team: ["Minutemen"]}}")
    assert render(view) =~ "Team: Minutemen"
    view |> element("#search-filters button[phx-click=clear_filters]") |> render_click()
    assert_patch(view, ~p"/search")
  end
end
