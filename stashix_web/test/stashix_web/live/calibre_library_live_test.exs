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

  test "settings pick whose read status a column holds", %{conn: conn, root: root} do
    {:ok, lib} = Library.create_library(%{name: "Cal", root_path: root, kind: :books, source: :calibre})

    lib
    |> Ecto.Changeset.change(
      calibre_state: %{
        "columns" => [
          %{"label" => "read", "name" => "Read", "type" => "bool", "multiple" => false},
          %{"label" => "notes", "name" => "Notes", "type" => "comments", "multiple" => false}
        ]
      }
    )
    |> Stashix.Repo.update!()

    user = Stashix.Repo.get_by!(Stashix.Accounts.User, username: "cal")
    {:ok, view, _html} = live(conn, ~p"/admin/libraries")
    view |> element("button[phx-click=edit_library][phx-value-id='#{lib.id}']") |> render_click()

    html = view |> element("#calibre-settings-#{lib.id}") |> render()
    assert html =~ "Read (#read)"
    # Only yes/no and number columns can hold read status.
    refute html =~ "#notes"

    view
    |> element("#calibre-settings-#{lib.id}")
    |> render_submit(%{"_id" => lib.id, "read_column" => "read", "read_user_id" => user.id})

    assert Stashix.Repo.get!(Library.Library, lib.id).calibre_settings == %{
             "read_column" => "read",
             "read_user_id" => user.id
           }

    # Saving started a sync; let it end inside the test.
    Enum.find_value(1..100, fn _ -> Stashix.Scanner.get_task_status(lib.id)[:done] || (Process.sleep(50) && nil) end)
  end

  test "a Calibre book's page", %{conn: conn, tmp_dir: tmp} do
    thumbs = Path.join(System.tmp_dir!(), "stashix_test_thumbs_#{System.unique_integer([:positive])}")
    Application.put_env(:stashix, :thumbnail_dir, thumbs)

    on_exit(fn ->
      Application.delete_env(:stashix, :thumbnail_dir)
      File.rm_rf(thumbs)
    end)

    root =
      CalibreFixtures.make_library(Path.join(tmp, "Shelf"), [
        %{
          title: "Good Omens",
          authors: ["Terry Pratchett"],
          rating: 9,
          identifiers: %{"google" => "g1", "goodreads" => "12067"},
          timestamp: "2021-06-01 10:00:00+00:00",
          formats: ["PDF", "MOBI", "EPUB"]
        }
      ])

    col = CalibreFixtures.add_custom_column(root, "read", "Read", "bool")
    CalibreFixtures.set_custom(root, col, 1, 1)
    shelf = CalibreFixtures.add_custom_column(root, "moods", "Moods", "text", multiple: true)
    CalibreFixtures.set_custom(root, shelf, 1, ["funny", "dark"])

    {:ok, lib} = Library.create_library(%{name: "Shelf", root_path: root, kind: :books, source: :calibre})
    {:ok, _} = Stashix.Calibre.Sync.run(lib)
    book = Stashix.Repo.get_by!(Stashix.Library.Book, title: "Good Omens")

    {:ok, view, html} = live(conn, ~p"/book/#{book}")
    assert html =~ "★★★★½ 4.5 / 5"
    assert has_element?(view, "#book-added-at")
    assert has_element?(view, "a[href='https://books.google.com/books?id=g1']")
    assert has_element?(view, "a[href='https://www.goodreads.com/book/show/12067']")
    # Custom columns, by their Calibre names.
    assert html =~ "Moods"
    assert html =~ "funny, dark"
    assert html =~ ~r/Read\s*<\/[^>]+>\s*<[^>]+>\s*Yes/

    # The format pills start on the EPUB.
    assert view |> element("span.bg-fg", "EPUB") |> has_element?()
  end

  test "author and series pages show Calibre's notes and links", %{conn: conn} do
    {:ok, lib} = Library.create_library(%{name: "Shelf", root_path: "/tmp/notes-shelf", kind: :books})

    {:ok, creator} =
      %Stashix.Library.Creator{}
      |> Stashix.Library.Creator.changeset(%{
        name: "Terry Pratchett",
        bio: "Wrote Discworld.",
        url: "https://example.com/terry"
      })
      |> Stashix.Repo.insert()

    {:ok, series} =
      %Stashix.Library.Series{}
      |> Stashix.Library.Series.changeset(%{
        name: "Discworld",
        library_id: lib.id,
        url: "https://example.com/discworld"
      })
      |> Stashix.Repo.insert()

    {:ok, book} = Library.create_book(%{title: "Mort", library_id: lib.id, series_id: series.id})

    {:ok, _} =
      Stashix.Metadata.Importer.replace_book_metadata(book, %{
        credits: [%{creator: "Terry Pratchett", roles: ["Writer"]}]
      })

    {:ok, view, _html} = live(conn, ~p"/creator/#{creator}")
    assert view |> element("#creator-bio") |> render() =~ "Wrote Discworld."
    assert has_element?(view, "#creator-url[href='https://example.com/terry']", "example.com")

    {:ok, view, _html} = live(conn, ~p"/series/#{series}")
    assert has_element?(view, "#series-url[href='https://example.com/discworld']")
  end
end
