# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.OpdsControllerTest do
  use StashixWeb.ConnCase, async: false

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.{BookFile, Series}

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "opds@example.com", username: "reader", password: "password1234"})
    {:ok, _app, password} = Accounts.create_app_password(user, "KOReader")

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: tmp})
    {:ok, other} = Library.create_library(%{name: "Locked", root_path: Path.join(tmp, "locked")})

    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, can_download: false})

    series = Repo.insert!(%Series{name: "Kickdown & Co", library_id: lib.id, path: Path.join(tmp, "k")})

    {:ok, issue} =
      Library.create_book(%{
        title: "Engines",
        issue_number: 2,
        page_count: 24,
        library_id: lib.id,
        series_id: series.id,
        summary: "Cars <fast>"
      })

    path = Path.join(tmp, "Kickdown 2.cbz")
    File.write!(path, "cbz")
    Repo.insert!(%BookFile{book_id: issue.id, path: path, format: :cbz, file_size: 3})

    {:ok, secret} = Library.create_book(%{title: "Behind the Door", library_id: other.id, type: "standalone"})

    %{
      conn: put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth("reader", password)),
      bare: conn,
      user: user,
      password: password,
      lib: lib,
      series: series,
      issue: issue,
      secret: secret
    }
  end

  test "asks for credentials without an app password", %{bare: conn, password: password} do
    conn = get(conn, ~p"/opds/v1.2/catalog")
    assert response(conn, 401)
    assert [challenge] = get_resp_header(conn, "www-authenticate")
    assert challenge =~ "Basic"

    # The account password is not enough, nor someone else's name.
    for {login, pass} <- [{"reader", "password1234"}, {"someone", password}] do
      conn = build_conn() |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth(login, pass))
      assert get(conn, ~p"/opds/v1.2/catalog") |> response(401)
    end
  end

  test "the email works as the user name", %{bare: conn, password: password} do
    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("OPDS@example.com", password))
      |> get(~p"/opds/v1.2/catalog")

    assert response(conn, 200)
  end

  test "the root is a navigation feed", %{conn: conn} do
    conn = get(conn, ~p"/opds/v1.2/catalog")
    body = response(conn, 200)

    assert [type] = get_resp_header(conn, "content-type")
    assert type =~ "kind=navigation"
    assert body =~ ~s(href="/opds/v1.2/new")
    assert body =~ ~s(href="/opds/v1.2/search.xml")
    assert {:ok, _} = parse(body)
  end

  test "libraries list only what the user can read", %{conn: conn, lib: lib} do
    body = conn |> get(~p"/opds/v1.2/libraries") |> response(200)
    assert body =~ "/opds/v1.2/libraries/#{lib.id}"
    refute body =~ "Locked"
  end

  test "a series lists its books with covers and a page stream", %{conn: conn, series: series, issue: issue} do
    body = conn |> get(~p"/opds/v1.2/series/#{series.id}") |> response(200)
    assert {:ok, _} = parse(body)

    assert body =~ "Kickdown &amp; Co #2 – Engines"
    assert body =~ "Cars &lt;fast&gt;"
    assert body =~ ~s(href="/opds/v1.2/books/#{issue.id}/cover")
    assert body =~ ~s(href="/opds/v1.2/books/#{issue.id}/page/{pageNumber}?w={maxWidth}" pse:count="24")
    # No download permission: no acquisition link.
    refute body =~ "opds-spec.org/acquisition"
  end

  test "books link their files when the user may download", %{conn: conn, user: user, lib: lib, issue: issue} do
    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, can_download: true})

    body = conn |> get(~p"/opds/v1.2/books") |> response(200)
    assert body =~ ~s(type="application/vnd.comicbook+zip" href="/opds/v1.2/books/#{issue.id}/download?formats=cbz")

    assert conn |> get(~p"/opds/v1.2/books/#{issue.id}/download?formats=cbz") |> response(200) == "cbz"
  end

  test "a Calibre book keeps its uuid, offers its best format first and is found by ISBN",
       %{conn: conn, user: user, lib: lib, tmp_dir: tmp} do
    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, can_download: true})

    {:ok, book} =
      Library.create_book(%{
        title: "Dune",
        library_id: lib.id,
        type: "standalone",
        isbn: "9780441013593",
        calibre_uuid: "11111111-2222-3333-4444-555555555555"
      })

    for format <- [:pdf, :epub, :mobi] do
      path = Path.join(tmp, "Dune.#{format}")
      File.write!(path, "x")
      Repo.insert!(%BookFile{book_id: book.id, path: path, format: format, file_size: 1})
    end

    body = conn |> get(~p"/opds/v1.2/search?q=isbn:978-0-441-01359-3") |> response(200)
    assert body =~ "<id>urn:uuid:11111111-2222-3333-4444-555555555555</id>"

    links = Regex.scan(~r/download\?formats=(\w+)/, body) |> Enum.map(&List.last/1)
    assert links == ["epub", "mobi", "pdf"]
  end

  test "downloads stay forbidden without the permission", %{conn: conn, issue: issue} do
    assert conn |> get(~p"/opds/v1.2/books/#{issue.id}/download?formats=cbz") |> response(403)
  end

  test "lists page with next links", %{conn: conn, lib: lib} do
    for n <- 1..55, do: Library.create_book(%{title: "Filler #{n}", library_id: lib.id, type: "standalone"})

    body = conn |> get(~p"/opds/v1.2/new?library=#{lib.id}") |> response(200)
    assert body =~ "<opensearch:totalResults>56</opensearch:totalResults>"
    assert body =~ ~s(rel="next" href="/opds/v1.2/new?library=#{lib.id}&amp;page=2")

    body = conn |> get(~p"/opds/v1.2/new?library=#{lib.id}&page=2") |> response(200)
    assert body =~ ~s(rel="previous")
    refute body =~ ~s(rel="next")
  end

  test "search finds readable books only", %{conn: conn} do
    body = conn |> get(~p"/opds/v1.2/search?q=engines") |> response(200)
    assert body =~ "Engines"

    body = conn |> get(~p"/opds/v1.2/search?q=door") |> response(200)
    refute body =~ "Behind the Door"

    assert conn |> get(~p"/opds/v1.2/search.xml") |> response(200) =~ "{searchTerms}"
  end

  test "books of unreadable libraries are not found", %{conn: conn, secret: secret} do
    assert_error_sent 404, fn -> get(conn, ~p"/opds/v1.2/books/#{secret.id}/cover") end
  end

  test "revoking an app password signs the app out", %{conn: conn, user: user} do
    [app] = Accounts.list_app_passwords(user)
    assert :ok = Accounts.delete_app_password(user, app.id)
    assert conn |> get(~p"/opds/v1.2/catalog") |> response(401)
  end

  defp parse(body) do
    {doc, _} = body |> :binary.bin_to_list() |> :xmerl_scan.string(quiet: true)
    {:ok, doc}
  catch
    :exit, reason -> {:error, reason}
  end
end
