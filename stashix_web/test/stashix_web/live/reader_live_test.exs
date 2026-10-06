defmodule StashixWeb.ReaderLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.Access
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
    {:ok, view, html} = live(conn, ~p"/read/#{first.id}")
    refute html =~ "reader-end"

    render_hook(view, "next_page", %{})
    refute has_element?(view, "#reader-end")

    render_hook(view, "next_page", %{})
    assert has_element?(view, "#reader-end")
    assert has_element?(view, ~s|#reader-end a[href="/read/#{second.id}"]|)
    assert has_element?(view, ~s|#reader-end a[href="/book/#{first.id}"]|)
    assert has_element?(view, ~s|#reader-end a[href="/series/#{first.series_id}"]|)
    assert Library.get_progress(user.id, first.id).current_page == 1

    render_hook(view, "prev_page", %{})
    refute has_element?(view, "#reader-end")

    render_hook(view, "next_page", %{})
    render_hook(view, "next_page", %{})
    assert_redirect(view, ~p"/read/#{second.id}")
  end

  test "closing saves the pending page and returns to the book page", ctx do
    %{conn: conn, user: user, first: first} = ctx
    {:ok, view, _html} = live(conn, ~p"/read/#{first.id}")

    render_hook(view, "next_page", %{})
    assert Library.get_progress(user.id, first.id) == nil

    render_hook(view, "close", %{})
    assert_redirect(view, ~p"/book/#{first.id}")
    assert Library.get_progress(user.id, first.id).current_page == 1
  end

  test "the last issue offers no next issue", %{conn: conn, second: second} do
    {:ok, view, _html} = live(conn, ~p"/read/#{second.id}")
    render_hook(view, "next_page", %{})
    html = render_hook(view, "next_page", %{})

    assert html =~ "The End"
    refute html =~ "Next issue"
    assert has_element?(view, ~s|#reader-end a[href="/series/#{second.series_id}"]|)

    # Nothing to carry on into: paging forward again stays put.
    assert render_hook(view, "next_page", %{}) =~ "The End"
  end

  defp write_cbz(dir, filename, pages) do
    files = for i <- 1..pages, do: {String.to_charlist("page#{i}.jpg"), "fake jpeg #{filename} #{i}"}
    {:ok, {_, data}} = :zip.create(String.to_charlist(Path.join(dir, filename)), files, [:memory])
    File.write!(Path.join(dir, filename), data)
  end
end
