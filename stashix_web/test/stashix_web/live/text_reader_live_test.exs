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

  test "a PDF poppler can't read is searched by the hook, which lists its hits", %{conn: conn, text: book} do
    {view, _html} = open(conn, book)
    render_hook(view, "loaded", %{"page_count" => 3})
    render_click(view, "open_panel", %{"panel" => "search"})

    view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})
    assert_push_event(view, "text:search", %{query: "whale", server: true})
    render_async(view)
    assert_push_event(view, "text:search", payload)
    assert payload == %{query: "whale"}

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

  if System.find_executable("pdftotext") do
    test "a PDF is searched on the server", %{conn: conn, user: user, tmp_dir: tmp} do
      {:ok, lib} = Library.create_library(%{name: "Papers", root_path: Path.join(tmp, "papers")})
      {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
      {:ok, book} = Library.create_book(%{title: "Paper", library_id: lib.id, page_count: 2})
      path = Stashix.PdfFixtures.make_pdf(Path.join(tmp, "paper.pdf"), [{612, 792}, {612, 792, "The white whale."}])
      Repo.insert!(%BookFile{book_id: book.id, path: path, format: :pdf, file_size: 8, content_kind: :text})

      {view, _html} = open(conn, book)
      render_click(view, "open_panel", %{"panel" => "search"})
      view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})
      assert_push_event(view, "text:search", %{query: "whale", server: true})
      render_async(view)

      assert has_element?(view, "#text-reader-panel mark", "whale")
      view |> element("#text-reader-panel li button") |> render_click()
      assert_push_event(view, "text:goto", %{page: 1, query: "whale"})
    end
  end

  test "a link out of the book asks first, and opens without saying where it came from",
       %{conn: conn, epub: book} do
    {view, _html} = open(conn, book)
    refute has_element?(view, "#external-link")

    render_hook(view, "external_link", %{"url" => "https://example.com/page?q=1"})
    assert has_element?(view, "#external-link", "https://example.com/page?q=1")

    assert has_element?(
             view,
             ~s|#external-link-open[href="https://example.com/page?q=1"][target="_blank"][rel="noopener noreferrer"]|
           )

    render_click(view, "close_external_link")
    refute has_element?(view, "#external-link")

    # Only web and mail links open.
    for url <- ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "https://", "/api/books"] do
      render_hook(view, "external_link", %{"url" => url})
      refute has_element?(view, "#external-link"), url
    end

    render_hook(view, "external_link", %{"url" => "mailto:author@example.com"})
    assert has_element?(view, ~s|#external-link-open[href="mailto:author@example.com"]|)
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

    test "progress from another app reopens at the same share of the book", %{conn: conn, user: user, epub: book} do
      {:ok, _} =
        Library.update_progress(Stashix.Library.Access.all(), user.id, book.id, 0,
          progression: 0.42,
          locator: %{"type" => "epub", "href" => "OEBPS/text/ch1.xhtml"}
        )

      {view, _html} = open(conn, book)
      assert has_element?(view, ~s|#epub-reader[data-fraction="0.42"]|)
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

    test "search runs on the server; a hit is a match in a section, named by the contents",
         %{conn: conn, epub: book} do
      {view, _html} = open(conn, book)

      render_hook(view, "outline", %{
        "items" => [%{"title" => "Loomings", "depth" => 0, "target" => "OEBPS/text/ch1.xhtml", "section" => 0}]
      })

      render_click(view, "open_panel", %{"panel" => "search"})
      view |> element("#text-reader-panel form") |> render_change(%{"q" => "ishmael"})
      assert_push_event(view, "text:search", %{query: "ishmael", server: true})
      render_async(view)

      assert has_element?(view, "#text-reader-panel mark", "Ishmael")
      assert has_element?(view, "#text-reader-panel li", "Loomings")
      assert render(view) =~ "1 match"
      view |> element("#text-reader-panel li button") |> render_click()
      assert_push_event(view, "text:goto", %{section: 0, n: 0, query: "ishmael"})
    end
  end

  describe "read-aloud" do
    test "controls drive the hook; speed and voice are saved", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 40})
      view |> element("#tts-toggle") |> render_click()

      # No voices yet: the controls wait for the hook's list.
      render_hook(view, "tts_voices", %{
        "voices" => [%{"name" => "Anna", "lang" => "de-DE"}, %{"name" => "Sam", "lang" => "en-US"}]
      })

      assert view |> element("#tts-settings select[name=voice] option:nth-child(2)") |> render() =~ "Sam (en-US)"

      view |> element("#tts-play") |> render_click()
      assert_push_event(view, "text:tts", %{action: "play", rate: 1.0, voice: ""})

      render_hook(view, "tts_state", %{"playing" => true})
      assert has_element?(view, "#tts-pause")
      view |> element("#tts-pause") |> render_click()
      assert_push_event(view, "text:tts", %{action: "pause"})

      view |> form("#tts-settings", %{"rate" => "1.5", "voice" => "Anna"}) |> render_change()
      assert_push_event(view, "text:tts", %{rate: 1.5, voice: "Anna"})
      assert %{"tts_rate" => 1.5, "tts_voice" => "Anna"} = Accounts.get_user!(user.id).reader_settings

      # Later view changes keep them.
      render_click(view, "set_font", %{"font" => "serif"})
      assert %{"tts_rate" => 1.5, "epub_font" => "serif"} = Accounts.get_user!(user.id).reader_settings

      view |> element("#tts-toggle") |> render_click()
      assert_push_event(view, "text:tts", %{action: "stop"})
      refute has_element?(view, "#tts-controls")
    end

    test "a browser without voices says so", %{conn: conn, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 40})
      view |> element("#tts-toggle") |> render_click()
      render_hook(view, "tts_voices", %{"voices" => []})
      assert has_element?(view, "#tts-controls", "no voices")
    end
  end

  describe "annotations" do
    test "a highlight from the hook is saved, listed, noted and removed", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 40})
      assert_push_event(view, "annotations:all", %{items: []})

      cfi = "epubcfi(/6/4!/4/2,/1:0,/1:15)"

      reply =
        render_hook(view, "annotate", %{
          "kind" => "highlight",
          "color" => "blue",
          "cfi" => cfi,
          "href" => "OEBPS/text/ch1.xhtml",
          "text" => "Call me Ishmael",
          "fraction" => 0.1,
          "edit" => true
        })

      assert reply =~ "Call me Ishmael"

      assert [%{id: id, kind: :highlight, color: "blue", locator: %{"type" => "epub", "cfi" => ^cfi}}] =
               Stashix.Annotations.list(user.id, book.id)

      assert_push_event(view, "annotations:put", %{item: %{id: ^id, color: "blue"}})

      # "edit" opened the Notes panel on it.
      assert has_element?(view, "#note-form-#{id} textarea")
      view |> form("#note-form-#{id}", %{"note" => "First line"}) |> render_submit()
      assert has_element?(view, "#note-#{id}", "First line")

      view |> element("#note-#{id} button[phx-click=annotation_goto]") |> render_click()
      assert_push_event(view, "text:goto", %{target: ^cfi})

      view |> element("#note-#{id} button[phx-value-color=pink]") |> render_click()
      assert_push_event(view, "annotations:put", %{item: %{id: ^id, color: "pink"}})

      view |> element("#note-#{id} button[phx-click=annotation_delete]") |> render_click()
      assert_push_event(view, "annotations:remove", %{id: ^id})
      assert Stashix.Annotations.list(user.id, book.id) == []
    end

    test "PDF: highlights keep their page and rects; bookmarks follow the page", %{conn: conn, user: user, text: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 3})
      render_hook(view, "page_changed", %{"page" => 1})

      render_hook(view, "annotate", %{
        "kind" => "highlight",
        "page" => 1,
        "rects" => [[0.1, 0.2, 0.5, 0.02]],
        "text" => "x"
      })

      assert [%{locator: %{"type" => "pdf", "page" => 1, "rects" => [[0.1, 0.2, 0.5, 0.02]]}, color: "yellow"}] =
               Stashix.Annotations.list(user.id, book.id)

      view |> element("#bookmark-toggle") |> render_click()
      assert has_element?(view, ~s|#bookmark-toggle[title="Remove bookmark"]|)

      assert [%{kind: :bookmark, locator: %{"page" => 1}}] =
               Stashix.Annotations.list(user.id, book.id) |> Enum.filter(&(&1.kind == :bookmark))

      render_hook(view, "page_changed", %{"page" => 2})
      assert has_element?(view, ~s|#bookmark-toggle[title="Bookmark this page"]|)
      render_hook(view, "page_changed", %{"page" => 1})
      view |> element("#bookmark-toggle") |> render_click()
      assert Enum.filter(Stashix.Annotations.list(user.id, book.id), &(&1.kind == :bookmark)) == []
    end

    test "?at= opens at a highlight", %{conn: conn, user: user, epub: book, text: pdf} do
      cfi = "epubcfi(/6/4!/4/2,/1:0,/1:4)"
      params = %{"kind" => "highlight", "color" => "yellow", "locator" => %{"type" => "epub", "cfi" => cfi}}
      {:ok, a} = Stashix.Annotations.create(Stashix.Library.Access.all(), user.id, book, params)
      {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book.id}/text?at=#{a.id}")
      assert has_element?(view, ~s|#epub-reader[data-cfi="#{cfi}"]|)

      params = %{"kind" => "bookmark", "locator" => %{"type" => "pdf", "page" => 2}}
      {:ok, b} = Stashix.Annotations.create(Stashix.Library.Access.all(), user.id, pdf, params)
      {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/read/#{pdf.id}?at=#{b.id}")
      {:ok, view, _html} = live_canonical(conn, to)
      assert has_element?(view, ~s|#pdf-reader[data-start="2"]|)
    end

    test "EPUB: the hook says which bookmark is showing", %{conn: conn, user: user, epub: book} do
      {view, _html} = open(conn, book)
      render_hook(view, "loaded", %{"page_count" => 40})
      render_hook(view, "page_changed", %{"page" => 3, "cfi" => "epubcfi(/6/4!/4,/2/1:0,/8/1:20)", "fraction" => 0.1})
      view |> element("#bookmark-toggle") |> render_click()

      assert [%{id: id, kind: :bookmark, locator: %{"cfi" => "epubcfi(/6/4!/4,/2/1:0,/8/1:20)"}}] =
               Stashix.Annotations.list(user.id, book.id)

      render_hook(view, "bookmark_here", %{"id" => nil})
      assert has_element?(view, ~s|#bookmark-toggle[title="Bookmark this page"]|)
      render_hook(view, "bookmark_here", %{"id" => id})
      assert has_element?(view, ~s|#bookmark-toggle[title="Remove bookmark"]|)
    end
  end

  test "a book in several formats switches between them in the View menu", %{conn: conn, epub: book, tmp_dir: tmp} do
    {view, _html} = open(conn, book)
    refute has_element?(view, "#text-format-epub")

    mobi = Stashix.EbookFixtures.make_mobi(Path.join(tmp, "moby.mobi"))
    Repo.insert!(%BookFile{book_id: book.id, path: mobi, format: :mobi, file_size: 1, content_kind: :text})

    {view, _html} = open(conn, book)
    assert has_element?(view, "#text-format-epub[aria-checked=true]")
    assert has_element?(view, "#text-format-mobi[aria-checked=false][href*='format=mobi']")

    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book}/text?format=mobi")
    assert has_element?(view, "#epub-reader[data-url$='file?format=mobi']")
    assert has_element?(view, "#text-format-mobi[aria-checked=true]")
  end

  describe "Kindle and FictionBook" do
    setup %{epub: epub, tmp_dir: tmp} do
      ebook = fn title, format, path ->
        {:ok, b} = Library.create_book(%{title: title, library_id: epub.library_id, page_count: 30})
        Repo.insert!(%BookFile{book_id: b.id, path: path, format: format, file_size: 1, content_kind: :text})
        b
      end

      %{
        mobi: ebook.("Kindle", :azw3, Stashix.EbookFixtures.make_mobi(Path.join(tmp, "k.azw3"))),
        fb2: ebook.("Fiction", :fb2, Stashix.EbookFixtures.make_fb2(Path.join(tmp, "f.fb2"))),
        locked: ebook.("Locked", :mobi, Stashix.EbookFixtures.make_mobi(Path.join(tmp, "l.mobi"), encryption: 2))
      }
    end

    test "open in the foliate view from the file, and save their spot", %{conn: conn, user: user, mobi: book} do
      {view, _html} = open(conn, book)
      url = "/api/books/#{book.id}/file?format=azw3"
      assert has_element?(view, ~s|#epub-reader[data-format="azw3"][data-url="#{url}"]|)

      render_hook(view, "loaded", %{"page_count" => 30})
      cfi = "epubcfi(/6/6!/4/2/1:0)"
      render_hook(view, "page_changed", %{"page" => 4, "cfi" => cfi, "href" => 2, "fraction" => 0.15})
      render_click(view, "exit", %{"to" => "book"})

      assert %{progression: 0.15, locator: %{"type" => "mobi", "cfi" => ^cfi, "href" => nil}} =
               Library.get_progress(user.id, book.id)

      {view, _html} = open(conn, book)
      assert has_element?(view, ~s|#epub-reader[data-cfi="#{cfi}"]|)
    end

    test "the hook searches them, with hits at a CFI", %{conn: conn, mobi: book} do
      {view, _html} = open(conn, book)
      render_click(view, "open_panel", %{"panel" => "search"})
      view |> element("#text-reader-panel form") |> render_change(%{"q" => "whale"})
      assert_push_event(view, "text:search", payload)
      assert payload == %{query: "whale"}

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

    test "FictionBook opens there too", %{conn: conn, fb2: book} do
      {view, _html} = open(conn, book)
      assert has_element?(view, ~s|#epub-reader[data-format="fb2"]|)
    end

    test "a DRM-protected book says so instead of opening", %{conn: conn, locked: book} do
      {view, html} = open(conn, book)
      refute has_element?(view, "#epub-reader")
      assert html =~ "DRM-protected"
    end
  end
end
