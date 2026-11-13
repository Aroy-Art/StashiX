# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SeriesLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{Access, BookCover}
  alias Stashix.Scanner

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "series@example.com", username: "serieslive", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    tmp = Path.join(System.tmp_dir!(), "stashix_series_#{System.unique_integer([:positive])}")
    series_dir = Path.join(tmp, "Kickdown (2024)")
    File.mkdir_p!(series_dir)
    on_exit(fn -> File.rm_rf!(tmp) end)

    for n <- 1..3, do: write_cbz(series_dir, "Kickdown 00#{n}.cbz")

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: tmp})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
    Scanner.scan_sync(lib.id)

    # Not every fake page makes a thumbnail; make sure each book has a cover row.
    books = Library.list_books(lib.id, access: Access.all())

    for b <- books,
        do: Repo.insert!(%BookCover{book_id: b.id, path: "/nonexistent/#{b.id}.webp"}, on_conflict: :nothing)

    %{conn: conn, user: user, series_id: hd(books).series_id}
  end

  test "data saver drops the fanned covers behind the hero cover", %{conn: conn, user: user, series_id: series_id} do
    {:ok, view, _html} = live_canonical(conn, ~p"/series/#{series_id}")
    assert has_element?(view, ".cover-stack-card")

    {:ok, _} = Accounts.update_ui_settings(user, %{"data_saver" => "on"})
    {:ok, view, _html} = live_canonical(conn, ~p"/series/#{series_id}")
    refute has_element?(view, ".cover-stack-card")
  end

  defp write_cbz(dir, filename) do
    {:ok, {_, data}} = :zip.create(String.to_charlist(filename), [{~c"page1.jpg", "fake jpeg #{filename}"}], [:memory])
    File.write!(Path.join(dir, filename), data)
  end
end
