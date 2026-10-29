# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SeriesEditComponentTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.Series

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "a@example.com", username: "adm", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics-series-edit"})

    {:ok, series} =
      Library.create_or_find_series(%{library_id: lib.id, name: "Batman", path: "/tmp/comics-series-edit/Batman"})

    {:ok, _} = Library.create_book(%{library_id: lib.id, series_id: series.id, title: "Batman 1", age_rating: :teen})
    %{conn: conn, series: series}
  end

  test "saves new fields, alternative names and locks", %{conn: conn, series: series} do
    {:ok, view, _} = live(conn, ~p"/series/#{series.id}?edit=true")

    view |> element("button[phx-value-field=name][phx-click=toggle_lock]") |> render_click()
    view |> element("button[phx-click=row_add][phx-value-field=alternative_names]") |> render_click()

    view
    |> element("#edit-series-dialog form")
    |> render_submit(%{
      "series" => %{
        "name" => "Batman",
        "status" => "Completed",
        "sort_name" => "Batman (2016)",
        "issue_count" => "85",
        "alternative_names" => %{"0" => %{"name" => "Batman Rebirth", "lang" => "en"}}
      }
    })

    series = Series |> Repo.get!(series.id) |> Repo.preload(:alternative_names)
    assert series.status == "Completed"
    assert series.sort_name == "Batman (2016)"
    assert series.issue_count == 85
    assert ["name"] = series.locked_fields
    assert [%{name: "Batman Rebirth", lang: "en"}] = series.alternative_names
  end

  test "age rating still cascades to the issues", %{conn: conn, series: series} do
    {:ok, view, _} = live(conn, ~p"/series/#{series.id}?edit=true")

    view
    |> element("#edit-series-dialog form")
    |> render_submit(%{"series" => %{"name" => "Batman"}, "age_rating" => "mature"})

    assert [%{age_rating: :mature}] = Library.list_books(series.library_id, access: Stashix.Library.Access.all())
  end

  test "language is pushed to issues from the edit dialog, skipping locked ones", %{conn: conn, series: series} do
    {:ok, locked} =
      Library.create_book(%{
        library_id: series.library_id,
        series_id: series.id,
        title: "Batman 2",
        language: "de",
        locked_fields: ["language"]
      })

    {:ok, view, _} = live(conn, ~p"/series/#{series.id}?edit=true")

    # The button carries the dialog's unsaved value.
    view
    |> element("#edit-series-form")
    |> render_change(%{"series" => %{"name" => "Batman", "language" => "ja"}})

    view |> element("#edit-series-dialog button[phx-click=open_push_language_dialog]") |> render_click()
    assert has_element?(view, "#push-language-dialog")
    assert render(view) =~ "1 of 1 issue will change"

    view |> element("#push-language-dialog button[phx-click=push_language_to_issues]") |> render_click()

    langs =
      Library.list_books(series.library_id, access: Stashix.Library.Access.all())
      |> Map.new(&{&1.id, &1.language})

    assert langs[locked.id] == "de"
    assert langs |> Map.delete(locked.id) |> Map.values() == ["ja"]
  end

  test "fill mode only sets issues without a language", %{series: series} do
    {:ok, _} = Library.create_book(%{library_id: series.library_id, series_id: series.id, title: "B2", language: nil})
    assert {:ok, [_]} = Library.set_series_language(series.id, "fr", only_empty: true)
    assert %{affected: [], unchanged: 2} = Library.push_language_preview(series.id, "fr", :fill)
  end

  test "age rating and publisher pushes skip issues that lock them", %{series: series} do
    {:ok, locked} =
      Library.create_book(%{
        library_id: series.library_id,
        series_id: series.id,
        title: "B2",
        age_rating: :teen,
        locked_fields: ["age_rating", "publisher"]
      })

    {:ok, ids} = Library.set_series_age_rating(series.id, "adult")
    refute locked.id in ids

    {:ok, pub} = Library.get_or_create_publisher("DC Comics")
    {:ok, ids} = Library.push_publishers_to_books(series.id, [pub.id], :replace)
    refute locked.id in ids
  end
end
