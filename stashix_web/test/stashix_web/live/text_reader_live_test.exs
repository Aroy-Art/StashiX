# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.TextReaderLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.BookFile

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "t@example.com", username: "textreader", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})

    book = fn title, kind ->
      {:ok, b} = Library.create_book(%{title: title, library_id: lib.id, page_count: 3})
      path = Path.join(tmp, "#{title}.pdf")
      File.write!(path, "%PDF-1.4")
      Repo.insert!(%BookFile{book_id: b.id, path: path, format: :pdf, file_size: 8, content_kind: kind})
      b
    end

    %{conn: conn, user: user, text: book.("Novel", :text), scan: book.("Scan", :images)}
  end

  defp open(conn, book) do
    {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/read/#{book.id}")
    assert to =~ "/text"
    {:ok, view, html} = live_canonical(conn, to)
    {view, html}
  end

  test "the comic reader sends text books here", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    assert has_element?(view, ~s|#pdf-reader[phx-hook="PdfReader"][data-url="/api/books/#{book.id}/file?format=pdf"]|)
  end

  test "books that open as pages are sent back to the comic reader", %{conn: conn, scan: book} do
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/read/#{book.id}/text")
    refute to =~ "/text"
  end

  test "the page count follows the PDF, and page changes save progress", %{conn: conn, user: user, text: book} do
    {view, _html} = open(conn, book)

    render_hook(view, "pdf_loaded", %{"page_count" => 5})
    assert Repo.reload(book).page_count == 5
    assert render(view) =~ "/ 5"

    render_hook(view, "page_changed", %{"page" => 2})
    render_click(view, "exit", %{"to" => "book"})
    assert Library.get_progress(user.id, book.id).current_page == 2
  end

  test "scrolling to the end marks the book read", %{conn: conn, user: user, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "pdf_loaded", %{"page_count" => 3})

    render_hook(view, "scroll_end", %{"visible" => true})
    assert has_element?(view, "#reader-end")
    assert Library.get_progress(user.id, book.id).current_page == 2
  end

  test "view settings are saved next to the comic reader's", %{conn: conn, user: user, text: book} do
    {:ok, _} = Accounts.save_reader_settings(user, %{"page_layout" => "webtoon"})
    {view, _html} = open(conn, book)

    render_click(view, "set_layout", %{"layout" => "paged"})
    render_click(view, "set_page_theme", %{"theme" => "night"})
    assert_push_event(view, "pdf:view", %{layout: "paged", theme: "night"})

    settings = Accounts.get_user!(user.id).reader_settings
    assert settings["text_layout"] == "paged"
    assert settings["text_theme"] == "night"
    assert settings["page_layout"] == "webtoon"
  end

  test "contents list the outline and jump to a page", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "pdf_loaded", %{"page_count" => 3})
    render_click(view, "open_panel", %{"panel" => "contents"})

    render_hook(view, "pdf_outline", %{
      "items" => [%{"title" => "Intro", "page" => 0, "depth" => 0}, %{"title" => "Methods", "page" => 2, "depth" => 1}]
    })

    assert has_element?(view, "#text-reader-panel button", "Methods")
    view |> element("#text-reader-panel button", "Methods") |> render_click()
    assert_push_event(view, "pdf:goto", %{page: 2})
  end

  test "search sends the query to the hook and lists its hits", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "pdf_loaded", %{"page_count" => 3})
    render_click(view, "open_panel", %{"panel" => "search"})

    view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})
    assert_push_event(view, "pdf:search", %{query: "whale"})

    render_hook(view, "pdf_search_results", %{
      "query" => "whale",
      "results" => [%{"page" => 1, "before" => "the ", "match" => "whale", "after" => " swam"}],
      "scanned" => 3,
      "done" => true
    })

    # Hits for an older query are dropped.
    render_hook(view, "pdf_search_results", %{
      "query" => "wha",
      "results" => [%{"page" => 0, "before" => "", "match" => "wha", "after" => ""}]
    })

    assert has_element?(view, "#text-reader-panel mark", "whale")
    assert render(view) =~ "1 match"

    view |> element("#text-reader-panel li button") |> render_click()
    assert_push_event(view, "pdf:goto", %{page: 1, query: "whale"})
  end
end
