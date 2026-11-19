# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CalibreLibraryLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper
  alias Stashix.CalibreFixtures

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} =
      Accounts.create_user(%{email: "cal@example.com", username: "cal", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    root = CalibreFixtures.make_library(Path.join(tmp, "Calibre"), [%{title: "Dune", authors: ["Frank Herbert"]}])
    %{conn: conn, root: root}
  end

  test "a folder with a metadata.db is offered as a Calibre library", %{conn: conn, root: root, tmp_dir: tmp} do
    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    view |> element("button", "Add Library") |> render_click()
    form = element(view, "form#library-form")

    render_change(form, %{"name" => "Comics", "root_path" => tmp})
    refute has_element?(view, "#library-form-calibre")

    render_change(form, %{"name" => "Books", "root_path" => root})
    assert has_element?(view, "#library-form-calibre")

    render_submit(form, %{"name" => "Books", "root_path" => root, "calibre" => "true"})
    lib = Enum.find(Library.list_libraries(%{role: :admin}), &(&1.name == "Books"))
    assert {lib.source, lib.kind} == {:calibre, :books}

    assert has_element?(view, "#library-source-label-#{lib.id}", "Calibre")
    assert has_element?(view, "button[phx-value-id='#{lib.id}']", "Full resync")

    # Creating it started the first sync.
    assert eventually(fn -> Stashix.Repo.get_by(Stashix.Library.Book, title: "Dune", library_id: lib.id) end)
    assert eventually(fn -> Stashix.Scanner.get_task_status(lib.id)[:done] end)
  end

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      result when result in [nil, false] and tries > 0 ->
        Process.sleep(50)
        eventually(fun, tries - 1)

      result ->
        result
    end
  end

  test "unticked, it's a plain folder library", %{conn: conn, root: root} do
    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    view |> element("button", "Add Library") |> render_click()

    view
    |> element("form#library-form")
    |> render_submit(%{"name" => "Plain", "root_path" => root, "calibre" => "false", "kind" => "books"})

    assert Enum.find(Library.list_libraries(%{role: :admin}), &(&1.name == "Plain")).source == :folders
  end

  test "the row shows the last sync and its problems", %{conn: conn, root: root} do
    {:ok, lib} = Library.create_library(%{name: "Cal", root_path: root, kind: :books, source: :calibre})

    lib
    |> Ecto.Changeset.change(
      calibre_state: %{
        "synced_at" => "2026-11-19T10:00:00",
        "summary" => %{"books" => 678, "missing_files" => 3, "skipped_formats" => %{"KEPUB" => 2}},
        "error" => nil
      }
    )
    |> Stashix.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    status = view |> element("#calibre-status-#{lib.id}") |> render()
    assert status =~ "678 books"
    assert status =~ "3 files missing"
    assert status =~ "KEPUB (2)"

    lib
    |> Ecto.Changeset.change(calibre_state: %{"error" => "No metadata.db in the library folder"})
    |> Stashix.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    assert view |> element("#calibre-status-#{lib.id}") |> render() =~ "Last sync failed: No metadata.db"
  end
end
