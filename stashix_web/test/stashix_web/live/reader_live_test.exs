# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.ReaderLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{Access, Series}
  alias Stashix.Scanner

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "reader@example.com", username: "reader", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    tmp = Path.join(System.tmp_dir!(), "stashix_reader_#{System.unique_integer([:positive])}")
    series_dir = Path.join(tmp, "Kickdown (2024)")
    File.mkdir_p!(series_dir)
    on_exit(fn -> File.rm_rf!(tmp) end)

    write_cbz(series_dir, "Kickdown 001.cbz", 2)
    write_cbz(series_dir, "Kickdown 002.cbz", 2)

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: tmp})
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
    Scanner.scan_sync(lib.id)

    [first, second] = Library.list_books(lib.id, access: Access.all()) |> Enum.sort_by(& &1.issue_number)
    %{conn: conn, user: user, first: first, second: second}
  end

  test "paging past the last page shows the end card and marks the book read", ctx do
    %{conn: conn, user: user, first: first, second: second} = ctx
    {:ok, view, html} = live_canonical(conn, ~p"/read/#{first.id}")
    refute html =~ "reader-end"

    render_hook(view, "next_page", %{})
    refute has_element?(view, "#reader-end")

    render_hook(view, "next_page", %{})
    assert has_element?(view, "#reader-end")
    assert has_element?(view, ~s|#reader-end a[href="#{~p"/read/#{Repo.preload(second, :series)}"}"]|)
    assert has_element?(view, ~s|#reader-end button[phx-value-to="book"]|)
    assert has_element?(view, ~s|#reader-end button[phx-value-to="series"]|)
    assert Library.get_progress(user.id, first.id).current_page == 1

    render_hook(view, "prev_page", %{})
    refute has_element?(view, "#reader-end")

    render_hook(view, "next_page", %{})
    render_hook(view, "next_page", %{})
    assert_redirect(view, ~p"/read/#{Repo.preload(second, :series)}")
  end

  test "data saver stops the reader preloading the next pages", %{conn: conn, user: user, first: first} do
    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{first.id}")
    assert has_element?(view, "#reader-preload img")

    {:ok, _} = Accounts.update_ui_settings(user, %{"data_saver" => "on"})
    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{first.id}")
    refute has_element?(view, "#reader-preload")
  end

  test "half issues render on the series, book and reader pages", %{conn: conn, second: second} do
    second |> Ecto.Changeset.change(issue_number: Decimal.new("1.5")) |> Stashix.Repo.update!()

    {:ok, _view, html} = live_canonical(conn, ~p"/series/#{second.series_id}")
    assert html =~ "#1.5"
    {:ok, _view, html} = live_canonical(conn, ~p"/book/#{second.id}")
    assert html =~ "#1.5"
    {:ok, _view, html} = live_canonical(conn, ~p"/read/#{second.id}")
    assert html =~ "#1.5"
  end

  test "closing saves the pending page and returns to the book page", ctx do
    %{conn: conn, user: user, first: first} = ctx
    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{first.id}")

    render_hook(view, "next_page", %{})
    assert Library.get_progress(user.id, first.id) == nil

    render_hook(view, "exit", %{"to" => "book"})
    assert_push_event(view, "reader:exit", %{to: to})
    assert to == ~p"/book/#{Repo.preload(first, :series)}"
    assert Library.get_progress(user.id, first.id).current_page == 1
  end

  test "the last issue offers no next issue", %{conn: conn, second: second} do
    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{second.id}")
    render_hook(view, "next_page", %{})
    html = render_hook(view, "next_page", %{})

    assert html =~ "The End"
    refute html =~ "Next issue"
    view |> element(~s|#reader-end button[phx-value-to="series"]|) |> render_click()
    assert_push_event(view, "reader:exit", %{to: to})
    assert to == ~p"/series/#{Repo.get!(Series, second.series_id)}"

    # Nothing to carry on into: paging forward again stays put.
    assert render_hook(view, "next_page", %{}) =~ "The End"
  end

  test "webtoon layout shows every page in one strip and tracks the scrolled page", ctx do
    %{conn: conn, user: user, first: first, second: second} = ctx
    {:ok, view, _html} = live_canonical(conn, ~p"/read/#{first.id}")

    render_click(view, "set_layout", %{"layout" => "webtoon"})
    assert has_element?(view, ~s|#webtoon-strip img[data-page="0"]|)
    assert has_element?(view, ~s|#webtoon-strip img[data-page="1"]|)
    refute has_element?(view, "#reading-area")
    assert Accounts.get_user!(user.id).reader_settings["page_layout"] == "webtoon"

    render_hook(view, "scroll_page", %{"page" => 1})
    assert render(view) =~ ~s|value="1"|

    # Paging keys become scroll jumps for the strip to carry out.
    render_hook(view, "prev_page", %{})
    assert_push_event(view, "reader:scroll-to", %{page: 0})
    render_hook(view, "next_page", %{})
    assert_push_event(view, "reader:scroll-to", %{page: :end})

    render_hook(view, "scroll_end", %{"visible" => true})
    assert has_element?(view, ~s|#webtoon-end #reader-end a[href="#{~p"/read/#{Repo.preload(second, :series)}"}"]|)
    assert Library.get_progress(user.id, first.id).current_page == 1

    render_hook(view, "scroll_end", %{"visible" => false})
    refute has_element?(view, "#reader-end")
  end

  describe "annotations" do
    test "a region marked on the page is saved and listed; mark mode toggles", %{conn: conn, user: user, first: book} do
      {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book.id}")
      assert has_element?(view, ~s|#annot-layer[phx-hook="ImageAnnotations"][data-mark="false"]|)

      render_hook(view, "annotations_load", %{})
      assert_push_event(view, "annotations:all", %{items: []})

      view |> element("#mark-toggle") |> render_click()
      assert has_element?(view, ~s|#annot-layer[data-mark="true"]|)

      render_hook(view, "annotate", %{
        "kind" => "highlight",
        "color" => "pink",
        "page" => 1,
        "rect" => [0.1, 0.2, 0.3, 0.4]
      })

      assert [
               %{
                 id: id,
                 color: "pink",
                 progression: 1.0,
                 locator: %{"type" => "image", "page" => 1, "rect" => [0.1, 0.2, 0.3, 0.4]}
               }
             ] =
               Stashix.Annotations.list(user.id, book.id)

      assert_push_event(view, "annotations:put", %{item: %{id: ^id}})

      view |> element("button[title=Notes]") |> render_click()
      assert has_element?(view, "#reader-notes-panel #note-#{id}", "Page 2")

      view |> element("#note-#{id} button[phx-click=annotation_goto]") |> render_click()
      assert has_element?(view, ~s|#reader-page-main[data-page="1"]|)
    end

    test "the book page lists them, and each opens the reader there", %{conn: conn, user: user, first: book} do
      params = %{
        "kind" => "highlight",
        "color" => "green",
        "locator" => %{"type" => "image", "page" => 1, "rect" => [0, 0, 0.5, 0.5]},
        "note" => "Big splash"
      }

      {:ok, a} = Stashix.Annotations.create(Access.all(), user.id, book, params)

      {:ok, view, _html} = live_canonical(conn, ~p"/book/#{book.id}")
      assert has_element?(view, "#book-highlights", "Big splash")
      assert has_element?(view, ~s|#book-highlights a[href$="?at=#{a.id}"]|)
      assert has_element?(view, ~s|#book-highlights a[href="/api/books/#{book.id}/annotations/export?format=md"]|)

      {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book.id}?at=#{a.id}")
      assert has_element?(view, ~s|#reader-page-main[data-page="1"]|)
    end

    test "the bookmark button bookmarks the page showing", %{conn: conn, user: user, first: book} do
      {:ok, view, _html} = live_canonical(conn, ~p"/read/#{book.id}")
      view |> element("#bookmark-toggle") |> render_click()

      assert [%{kind: :bookmark, locator: %{"type" => "image", "page" => 0}}] =
               Stashix.Annotations.list(user.id, book.id)

      assert has_element?(view, ~s|#bookmark-toggle[title="Remove bookmark"]|)

      render_hook(view, "next_page", %{})
      assert has_element?(view, ~s|#bookmark-toggle[title="Bookmark this page"]|)
      render_hook(view, "prev_page", %{})
      view |> element("#bookmark-toggle") |> render_click()
      assert Stashix.Annotations.list(user.id, book.id) == []
    end
  end

  defp write_cbz(dir, filename, pages) do
    files = for i <- 1..pages, do: {String.to_charlist("page#{i}.jpg"), "fake jpeg #{filename} #{i}"}
    {:ok, {_, data}} = :zip.create(String.to_charlist(Path.join(dir, filename)), files, [:memory])
    File.write!(Path.join(dir, filename), data)
  end
end
