# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.BookEditComponentTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.Book
  alias Stashix.Metadata.Importer

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "a@example.com", username: "adm", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics-edit"})
    {:ok, book} = Library.create_book(%{library_id: lib.id, type: "standalone", title: "Old Title"})

    {:ok, _} =
      Importer.replace_book_metadata(book, %{
        characters: [%{name: "Batman", external_id: "10"}],
        credits: [%{creator: "Tom King", roles: ["Writer"]}]
      })

    %{conn: conn, book: book}
  end

  defp open(conn, book) do
    {:ok, view, _html} = live(conn, ~p"/book/#{book.id}?edit=true")
    view
  end

  defp form(view), do: element(view, "#edit-metadata-dialog form")

  defp reload(book), do: Book |> Repo.get!(book.id) |> Repo.preload([:characters, :tags, credits: :creator])

  test "shows every tab and saves scalar fields, including new spec fields", %{conn: conn, book: book} do
    view = open(conn, book)
    html = render(view)

    for tab <- ["General", "Dates &amp; IDs", "People", "Story", "Publishing &amp; links", "ComicInfo extras"],
        do: assert(html =~ tab)

    form(view)
    |> render_submit(%{
      "book" => %{
        "title" => "New Title",
        "manga" => "YesAndRightToLeft",
        "black_and_white" => "true",
        "series_group" => "Bat-family",
        "cover_date" => "2016-08-01",
        "characters" => %{"0" => %{"name" => "Batman", "external_id" => "10"}},
        "credits" => %{"0" => %{"creator" => "Tom King", "role" => "Writer"}}
      }
    })

    book = reload(book)
    assert book.title == "New Title"
    assert book.manga == "YesAndRightToLeft"
    assert book.black_and_white == true
    assert book.series_group == "Bat-family"
    assert book.cover_date == ~D[2016-08-01]
    assert [%{name: "Batman", external_id: "10"}] = book.characters
  end

  test "chips and rows are added and removed", %{conn: conn, book: book} do
    view = open(conn, book)

    view |> element("input[phx-value-field=tags]") |> render_keydown(%{"key" => "Enter", "value" => "noir"})
    view |> element("button[phx-click=row_add][phx-value-field=credits]") |> render_click()
    view |> element("button[aria-label='Remove Batman']") |> render_click()
    html = render(view)
    assert html =~ "noir"
    assert html =~ ~s(name="book[credits][1][creator]")

    form(view)
    |> render_submit(%{
      "book" => %{
        "title" => "Old Title",
        "tags" => %{"0" => %{"name" => "noir"}},
        "credits" => %{
          "0" => %{"creator" => "Tom King", "role" => "Writer"},
          "1" => %{"creator" => "Mitch Gerads", "role" => "Artist"}
        }
      }
    })

    book = reload(book)
    assert Enum.map(book.tags, & &1.name) == ["noir"]
    assert book.characters == []

    assert book.credits |> Enum.map(&{&1.creator.name, &1.role}) |> Enum.sort() == [
             {"Mitch Gerads", :Artist},
             {"Tom King", :Writer}
           ]
  end

  test "a field locked in the dialog is saved as locked and goes read-only", %{conn: conn, book: book} do
    view = open(conn, book)
    view |> element("button[phx-value-field=title][phx-click=toggle_lock]") |> render_click()

    assert has_element?(view, "input[name='book[title]'][readonly]")
    form(view) |> render_submit(%{"book" => %{"title" => "Old Title"}})

    assert "title" in reload(book).locked_fields
  end

  test "a field that stays locked can't be changed by a crafted submit", %{conn: conn, book: book} do
    {:ok, book} = Library.update_book(book, %{locked_fields: ["title", "characters"]})
    view = open(conn, book)

    form(view) |> render_submit(%{"book" => %{"title" => "Hacked", "characters" => %{}}})

    book = reload(book)
    assert book.title == "Old Title"
    assert [%{name: "Batman"}] = book.characters
  end

  test "language is picked from a searchable list, keeping unknown codes", %{conn: conn, book: book} do
    {:ok, book} = Library.update_book(book, %{language: "pt-BR"})
    view = open(conn, book)

    assert has_element?(view, "#edit-book-language[data-select] input[name='book[language]'][value='pt-BR']")
    assert has_element?(view, "#edit-book-language [data-menu-filter]")
    assert has_element?(view, "#edit-book-language [data-value='ja']", "Japanese (ja)")

    form(view) |> render_submit(%{"book" => %{"title" => "Old Title", "language" => "ja"}})
    assert reload(book).language == "ja"
  end

  test "an imprint needs a publisher", %{conn: conn, book: book} do
    view = open(conn, book)
    html = form(view) |> render_submit(%{"book" => %{"title" => "Old Title", "imprint" => "Black Label"}})
    assert html =~ "An imprint needs a publisher"
  end
end
