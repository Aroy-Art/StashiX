# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.ReadableUrlsTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo, Slug}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{Creator, Series}
  alias StashixWeb.Live.CanonicalUrl

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "admin@example.com", username: "admin", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})
    series = Repo.insert!(%Series{name: "Saga", start_year: 2012, library_id: lib.id})

    {:ok, book} =
      Library.create_book(%{
        library_id: lib.id,
        series_id: series.id,
        type: "issue",
        title: "Chapter One",
        issue_number: 1
      })

    %{conn: conn, lib: lib, series: series, book: Repo.preload(book, :series)}
  end

  test "slug links open the page directly", %{conn: conn, series: series, book: book, lib: lib} do
    assert {:ok, _view, html} = live(conn, ~p"/series/#{series}")
    assert html =~ "Saga"

    assert {:ok, _view, _html} = live(conn, ~p"/book/#{book}")
    assert {:ok, _view, _html} = live(conn, ~p"/library/#{lib}/books")
  end

  test "full UUIDs, bare short ids and stale slugs redirect to the canonical URL",
       %{conn: conn, series: series, book: book} do
    canonical = ~p"/series/#{series}"
    assert canonical == "/series/saga-2012-" <> Slug.short(series.id)

    for param <- [series.id, Slug.short(series.id), "old-name-#{Slug.short(series.id)}"] do
      assert {:error, {:live_redirect, %{to: ^canonical}}} = live(conn, ~p"/series/#{param}")
    end

    canonical_book = "/book/saga-2012-001-" <> Slug.short(book.id)
    assert {:error, {:live_redirect, %{to: ^canonical_book}}} = live(conn, ~p"/book/#{book.id}")
  end

  test "the redirect keeps sub-paths and query strings", %{conn: conn, lib: lib} do
    to = "/library/comics-#{Slug.short(lib.id)}/books?page=1&sort=title_desc"

    assert {:error, {:live_redirect, %{to: ^to}}} =
             live(conn, ~p"/library/#{lib.id}/books?#{[page: 1, sort: "title_desc"]}")
  end

  test "creators and publishers get slugs too", %{conn: conn} do
    walt = Repo.insert!(%Creator{name: "Walt Simonson"})
    {:ok, image} = Library.get_or_create_publisher("Image Comics")

    assert {:error, {:live_redirect, %{to: "/creator/walt-simonson-" <> _}}} = live(conn, ~p"/creator/#{walt.id}")
    assert {:ok, _view, html} = live(conn, ~p"/creator/#{walt}")
    assert html =~ "Walt Simonson"

    assert {:error, {:live_redirect, %{to: "/publisher/image-comics-" <> _}}} = live(conn, ~p"/publisher/#{image.id}")
  end

  test "unknown ids 404", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/series/saga-000000000000") end
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/book/not-a-book") end
  end

  test "canonical_path/3 leaves canonical params alone", %{series: series} do
    param = Phoenix.Param.to_param(series)
    assert CanonicalUrl.canonical_path(param, "http://x/series/#{param}?edit=true", series) == nil

    assert CanonicalUrl.canonical_path(series.id, "http://x/series/#{series.id}?edit=true", series) ==
             "/series/#{param}?edit=true"
  end
end
