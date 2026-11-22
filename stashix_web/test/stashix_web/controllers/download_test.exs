# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.DownloadTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.{BookFile, Series}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "dl@example.com", username: "downloader", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: tmp})

    {:ok, _} =
      Library.set_library_permission(%{
        user_id: user.id,
        library_id: lib.id,
        can_read: true,
        max_age_rating: :teen,
        can_download: true
      })

    series = Repo.insert!(%Series{name: "Kickdown", library_id: lib.id})

    book = fn n, rating, files ->
      {:ok, b} =
        Library.create_book(%{
          title: "Kickdown #{n}",
          issue_number: n,
          age_rating: rating,
          library_id: lib.id,
          series_id: series.id
        })

      for {rel, data} <- files do
        path = Path.join(tmp, rel)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, data)
        format = path |> Path.extname() |> String.trim_leading(".") |> String.to_existing_atom()
        Repo.insert!(%BookFile{book_id: b.id, path: path, format: format, file_size: byte_size(data)})
      end

      b
    end

    %{
      conn: conn,
      user: user,
      lib: lib,
      series: series,
      # Same cbz filename in two folders, to check names are kept apart in the ZIP.
      first: book.(1, :teen, [{"a/Kickdown.cbz", "cbz one"}, {"a/Kickdown 1.pdf", "pdf one"}]),
      second: book.(2, :everyone, [{"b/Kickdown.cbz", "cbz two"}]),
      hidden: book.(3, :adult, [{"c/Kickdown 3.cbz", "cbz three"}])
    }
  end

  defp unzip(conn) do
    assert response_content_type(conn, :zip) =~ "application/zip"
    assert get_resp_header(conn, "content-length") == [to_string(byte_size(conn.resp_body))]
    {:ok, files} = :zip.unzip(conn.resp_body, [:memory])
    Map.new(files, fn {name, data} -> {List.to_string(name), data} end)
  end

  test "an issue downloads one format as the file itself", %{conn: conn, first: first} do
    conn = get(conn, ~p"/api/books/#{first.id}/download?formats=pdf")

    assert response(conn, 200) == "pdf one"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "Kickdown%201.pdf"
  end

  test "an issue downloads all its formats as a ZIP", %{conn: conn, first: first} do
    conn = get(conn, ~p"/api/books/#{first.id}/download")

    assert unzip(conn) == %{"Kickdown.cbz" => "cbz one", "Kickdown 1.pdf" => "pdf one"}
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(filename="Kickdown%201.zip")
  end

  test "a format the issue lacks is a 404", %{conn: conn, second: second} do
    conn = get(conn, ~p"/api/books/#{second.id}/download?formats=pdf")
    assert json_response(conn, 404)
  end

  test "hidden issues cannot be downloaded", %{conn: conn, hidden: hidden} do
    assert_error_sent 404, fn -> get(conn, ~p"/api/books/#{hidden.id}/download") end
  end

  test "a series downloads the chosen formats of its visible issues", %{conn: conn, series: series} do
    conn = get(conn, ~p"/api/series/#{series.id}/download?formats=cbz")

    assert unzip(conn) == %{"Kickdown.cbz" => "cbz one", "Kickdown (2).cbz" => "cbz two"}
  end

  test "a series downloads every format by default", %{conn: conn, series: series} do
    files = conn |> get(~p"/api/series/#{series.id}/download") |> unzip()
    assert Map.keys(files) |> Enum.sort() == ["Kickdown (2).cbz", "Kickdown 1.pdf", "Kickdown.cbz"]
  end

  test "the issue page offers each format", %{conn: conn, first: first, second: second} do
    {:ok, view, _html} = live_canonical(conn, ~p"/book/#{first.id}")
    assert has_element?(view, ~s(#download-menu a[href="/api/books/#{first.id}/download?formats=pdf"]))
    assert has_element?(view, ~s(#download-menu a[href="/api/books/#{first.id}/download"]))

    {:ok, view, _html} = live_canonical(conn, ~p"/book/#{second.id}")
    refute has_element?(view, "#download-menu")
    assert has_element?(view, ~s(a[href="/api/books/#{second.id}/download?formats=cbz"]))
  end

  test "the series page lets the user pick formats", %{conn: conn, series: series} do
    {:ok, view, _html} = live_canonical(conn, ~p"/series/#{series.id}")

    view |> element("#series-download") |> render_click()
    assert has_element?(view, ~s(#download-dialog a[href="/api/series/#{series.id}/download?formats=cbz%2Cpdf"]))

    view |> form("#download-formats-form", %{"formats" => ["pdf"]}) |> render_change()
    assert has_element?(view, ~s(#download-dialog a[href="/api/series/#{series.id}/download?formats=pdf"]))

    # Unticking the last box sends no `formats` at all.
    render_hook(view, "set_download_formats", %{})
    assert has_element?(view, "#download-dialog button[disabled]", "Download")
  end

  test "a collection downloads its books in order, one file each", ctx do
    %{conn: conn, user: user, series: series, second: second} = ctx
    access = Stashix.Library.Access.for_user(user)
    {:ok, c} = Stashix.Collections.create(user, %{name: "Kick/collection"})
    {:ok, _} = Stashix.Collections.add(user, access, c, {:book, second.id})
    {:ok, _} = Stashix.Collections.add(user, access, c, {:series, series.id})

    conn = get(conn, ~p"/api/collections/#{c.id}/download")
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "Kick_collection.zip"

    # #2 first (its own entry), then the rest of the series; the adult #3 is
    # out of reach; #1's best format is the PDF.
    assert unzip(conn) == %{"001 - Kickdown.cbz" => "cbz two", "002 - Kickdown 1.pdf" => "pdf one"}

    {:ok, view, _html} = live(ctx.conn, ~p"/collection/#{c.id}")
    assert has_element?(view, ~s|#collection-download[href="/api/collections/#{c.id}/download"]|)
  end

  test "a collection's formats can be picked", %{conn: conn, user: user, series: series} do
    {:ok, c} = Stashix.Collections.create(user, %{name: "Comics only"})
    {:ok, _} = Stashix.Collections.add(user, Stashix.Library.Access.for_user(user), c, {:series, series.id})

    assert unzip(get(conn, ~p"/api/collections/#{c.id}/download?formats=cbz")) |> Map.keys() ==
             ["001 - Kickdown.cbz", "002 - Kickdown.cbz"]
  end

  test "picked books and series download as one ZIP, in the order picked", ctx do
    %{conn: conn, series: series, second: second} = ctx
    token = Plug.CSRFProtection.get_csrf_token()
    conn = Plug.Test.init_test_session(conn, %{"_csrf_token" => Plug.CSRFProtection.dump_state()})
    items = ["book:#{second.id}", "series:#{series.id}", "nonsense", "book:not-a-uuid"]

    conn = post(conn, ~p"/api/download", %{"_csrf_token" => token, "items" => items})
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "Stashix.zip"
    assert unzip(conn) == %{"001 - Kickdown.cbz" => "cbz two", "002 - Kickdown 1.pdf" => "pdf one"}

    # Without the token: refused.
    unsafe = Plug.Conn.put_private(ctx.conn, :plug_skip_csrf_protection, false)
    assert_error_sent 403, fn -> post(unsafe, ~p"/api/download", %{"items" => items}) end
  end

  describe "without download permission" do
    setup %{user: user, lib: lib} do
      {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_download: false})
      :ok
    end

    test "downloads are refused", %{conn: conn, first: first, series: series} do
      assert json_response(get(conn, ~p"/api/books/#{first.id}/download"), 403)
      assert json_response(get(conn, ~p"/api/series/#{series.id}/download"), 403)
    end

    test "the pages offer no download", %{conn: conn, first: first, series: series} do
      {:ok, view, _html} = live_canonical(conn, ~p"/book/#{first.id}")
      refute has_element?(view, "#download-menu")
      refute has_element?(view, ~s(a[href^="/api/books/#{first.id}/download"]))

      {:ok, view, _html} = live_canonical(conn, ~p"/series/#{series.id}")
      refute has_element?(view, "#series-download")
    end
  end

  test "new permissions do not allow downloads", %{lib: lib} do
    {:ok, other} = Accounts.create_user(%{email: "new@example.com", username: "newbie", password: "password1234"})
    {:ok, _} = Library.set_library_permission(%{user_id: other.id, library_id: lib.id, can_read: true})

    refute Stashix.Library.Access.can_download?(Stashix.Library.Access.for_user(other), lib.id)
    assert Stashix.Library.Access.can_download?(Stashix.Library.Access.all(), lib.id)
  end
end
