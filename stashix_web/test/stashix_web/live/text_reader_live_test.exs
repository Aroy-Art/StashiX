# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.TextReaderLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.BookFile

  import Stashix.EpubFixtures

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

    epub = fn title ->
      {:ok, b} = Library.create_book(%{title: title, library_id: lib.id, page_count: 40})
      path = make_epub(Path.join(tmp, "#{title}.epub"), [{:text, "Call me Ishmael."}])
      Repo.insert!(%BookFile{book_id: b.id, path: path, format: :epub, file_size: 1, content_kind: :text})
      b
    end

    %{conn: conn, user: user, text: book.("Novel", :text), scan: book.("Scan", :images), epub: epub.("Moby")}
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

    render_hook(view, "loaded", %{"page_count" => 5})
    assert Repo.reload(book).page_count == 5
    assert render(view) =~ "/ 5"

    render_hook(view, "page_changed", %{"page" => 2})
    render_click(view, "exit", %{"to" => "book"})

    assert %{current_page: 2, progression: 0.5, locator: %{"type" => "pdf", "page" => 2}} =
             Library.get_progress(user.id, book.id)
  end

  test "scrolling to the end marks the book read", %{conn: conn, user: user, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "loaded", %{"page_count" => 3})

    render_hook(view, "scroll_end", %{"visible" => true})
    assert has_element?(view, "#reader-end")
    assert %{current_page: 2, progression: 1.0} = Library.get_progress(user.id, book.id)
  end

  test "view settings are saved next to the comic reader's", %{conn: conn, user: user, text: book} do
    {:ok, _} = Accounts.save_reader_settings(user, %{"page_layout" => "webtoon"})
    {view, _html} = open(conn, book)

    render_click(view, "set_layout", %{"layout" => "paged"})
    render_click(view, "set_page_theme", %{"theme" => "night"})
    assert_push_event(view, "text:view", %{layout: "paged", theme: "night"})

    settings = Accounts.get_user!(user.id).reader_settings
    assert settings["text_layout"] == "paged"
    assert settings["text_theme"] == "night"
    assert settings["page_layout"] == "webtoon"
  end

  test "contents list the outline and jump to a page", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "loaded", %{"page_count" => 3})
    render_click(view, "open_panel", %{"panel" => "contents"})

    render_hook(view, "outline", %{
      "items" => [%{"title" => "Intro", "page" => 0, "depth" => 0}, %{"title" => "Methods", "page" => 2, "depth" => 1}]
    })

    assert has_element?(view, "#text-reader-panel button", "Methods")
    view |> element("#text-reader-panel button", "Methods") |> render_click()
    assert_push_event(view, "text:goto", %{page: 2})
  end

  test "search sends the query to the hook and lists its hits", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "loaded", %{"page_count" => 3})
    render_click(view, "open_panel", %{"panel" => "search"})

    view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})
    assert_push_event(view, "text:search", %{query: "whale"})

    render_hook(view, "search_results", %{
      "query" => "whale",
      "results" => [%{"page" => 1, "before" => "the ", "match" => "whale", "after" => " swam"}],
      "scanned" => 3,
      "done" => true
    })

    # Hits for an older query are dropped.
    render_hook(view, "search_results", %{
      "query" => "wha",
      "results" => [%{"page" => 0, "before" => "", "match" => "wha", "after" => ""}]
    })

    assert has_element?(view, "#text-reader-panel mark", "whale")
    assert render(view) =~ "1 match"

    view |> element("#text-reader-panel li button") |> render_click()
    assert_push_event(view, "text:goto", %{page: 1, query: "whale"})
  end

  test "the reader page runs under a CSP that only allows our own scripts", %{conn: conn, text: book} do
    # The id path redirects to the canonical slug one.
    conn = get(conn, ~p"/read/#{book.id}/text")
    conn = get(recycle(conn), redirected_to(conn))
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ ~r/script-src 'self' 'nonce-[^']+'/
    refute csp =~ "unsafe-inline' 'wasm"
    [_, nonce] = Regex.run(~r/'nonce-([^']+)'/, csp)
    assert html_response(conn, 200) =~ ~s(<script nonce="#{nonce}">)
  end

  describe "EPUB" do
    test "opens in the EPUB view with the reader's text settings", %{conn: conn, epub: book} do
      {view, _html} = open(conn, book)
      assert has_element?(view, ~s|#epub-reader[phx-hook="EpubReader"][data-url="/api/books/#{book.id}/epub"]|)
      refute has_element?(view, "#pdf-reader")
      assert render(view) =~ "%"
    end

    test "locations update the count and progress; contents follow the chapter", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 52})
      render_hook(view, "outline", %{"items" => [%{"title" => "Loomings", "target" => "ch1.xhtml", "depth" => 0}]})

      render_hook(view, "page_changed", %{"page" => 13, "total" => 52, "toc" => "ch1.xhtml"})
      assert Repo.reload(book).page_count == 52

      render_click(view, "open_panel", %{"panel" => "contents"})
      assert has_element?(view, ~s|#text-reader-panel button.border-ink[phx-value-target="ch1.xhtml"]|)

      view |> element("#text-reader-panel button", "Loomings") |> render_click()
      assert_push_event(view, "text:goto", %{target: "ch1.xhtml"})

      render_click(view, "exit", %{"to" => "book"})
      assert Library.get_progress(user.id, book.id).current_page == 13
    end

    test "the exact spot is saved and the book reopens there", %{conn: conn, user: user, epub: book} do
      {view, html} = open(conn, book)
      refute html =~ "data-cfi"
      render_hook(view, "loaded", %{"page_count" => 40})

      cfi = "epubcfi(/6/4!/4/2/1:120)"
      params = %{"page" => 9, "total" => 40, "cfi" => cfi, "href" => "OEBPS/text/ch1.xhtml", "fraction" => 0.23}
      render_hook(view, "page_changed", params)
      render_click(view, "exit", %{"to" => "book"})

      assert %{progression: 0.23, locator: %{"type" => "epub", "cfi" => ^cfi, "href" => "OEBPS/text/ch1.xhtml"}} =
               Library.get_progress(user.id, book.id)

      {view, _html} = open(conn, book)
      assert has_element?(view, ~s|#epub-reader[data-cfi="#{cfi}"][data-start="9"]|)

      # Starting over ignores it.
      {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book.id}/text?page=0")
      assert has_element?(view, ~s|#epub-reader[data-start="0"]|)
      refute has_element?(view, "#epub-reader[data-cfi]")
    end

    test "turning pages inside one location still saves the spot", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 40})
      render_hook(view, "page_changed", %{"page" => 9, "cfi" => "epubcfi(/6/4!/4/2/1:0)", "fraction" => 0.2})
      render_hook(view, "page_changed", %{"page" => 9, "cfi" => "epubcfi(/6/4!/4/8/1:0)", "fraction" => 0.21})
      render_click(view, "exit", %{"to" => "book"})

      assert %{locator: %{"cfi" => "epubcfi(/6/4!/4/8/1:0)"}} = Library.get_progress(user.id, book.id)
    end

    test "text size, font and spacing are saved and sent to the hook", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)

      render_click(view, "zoom", %{"by" => "1"})
      assert_push_event(view, "text:view", %{size: 110})
      render_click(view, "set_font", %{"font" => "serif"})
      render_click(view, "set_layout", %{"layout" => "scroll"})
      assert_push_event(view, "text:view", %{font: "serif", layout: "scroll"})

      settings = Accounts.get_user!(user.id).reader_settings
      assert %{"epub_size" => 110, "epub_font" => "serif", "epub_layout" => "scroll"} = settings
      refute Map.has_key?(settings, "text_layout")
    end

    test "search hits point into the book and name the chapter", %{conn: conn, epub: book} do
      {view, _html} = open(conn, book)
      render_click(view, "open_panel", %{"panel" => "search"})
      view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})

      render_hook(view, "search_results", %{
        "query" => "whale",
        "results" => [
          %{
            "target" => "epubcfi(/6/4!/4/2)",
            "label" => "Loomings",
            "before" => "a ",
            "match" => "whale",
            "after" => "!"
          }
        ],
        "done" => true
      })

      assert has_element?(view, "#text-reader-panel li", "Loomings")
      view |> element("#text-reader-panel li button") |> render_click()
      assert_push_event(view, "text:goto", %{target: "epubcfi(/6/4!/4/2)", query: "whale"})
    end
  end
end
