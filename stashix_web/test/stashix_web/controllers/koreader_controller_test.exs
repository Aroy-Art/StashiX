# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.KoreaderControllerTest do
  use StashixWeb.ConnCase, async: false

  alias Stashix.{Accounts, Koreader, Library, Repo}
  alias Stashix.Library.BookFile

  @moduletag :tmp_dir

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "ko@example.com", username: "koreader", password: "password1234"})
    {:ok, _app, password} = Accounts.create_app_password(user, "Kobo")
    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp, kind: :books})

    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})

    {:ok, comic} = Library.create_book(%{title: "Strip", library_id: lib.id, type: "standalone", page_count: 20})
    comic_file = add_file(comic, Path.join(tmp, "strip.cbz"), :cbz, :crypto.strong_rand_bytes(5000))

    {:ok, novel} =
      Library.create_book(%{title: "Novel", library_id: lib.id, type: "standalone", content_kind: :text})

    novel_file = add_file(novel, Path.join(tmp, "novel.epub"), :epub, epub())

    key = Base.encode16(:crypto.hash(:md5, password), case: :lower)

    %{
      conn: conn |> put_req_header("x-auth-user", "koreader") |> put_req_header("x-auth-key", key),
      bare: conn,
      user: user,
      comic: comic,
      comic_hash: Koreader.partial_md5(comic_file.path),
      novel: novel,
      novel_hash: Koreader.partial_md5(novel_file.path)
    }
  end

  defp add_file(book, path, format, data) do
    File.write!(path, data)

    Repo.insert!(%BookFile{
      book_id: book.id,
      path: path,
      format: format,
      file_size: byte_size(data),
      file_hash: Stashix.Scanner.compute_hash(path, byte_size(data))
    })
  end

  # A two-chapter EPUB.
  defp epub do
    files = [
      {~c"mimetype", "application/epub+zip"},
      {~c"META-INF/container.xml",
       ~s(<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>)},
      {~c"OEBPS/content.opf",
       ~s(<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest><item id="a" href="ch1.xhtml" media-type="application/xhtml+xml"/><item id="b" href="ch2.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>)},
      {~c"OEBPS/ch1.xhtml", "<html><body><p>One</p></body></html>"},
      {~c"OEBPS/ch2.xhtml", "<html><body><p>Two</p></body></html>"}
    ]

    {:ok, {_, zip}} = :zip.create(~c"book.epub", files, [:memory])
    zip
  end

  defp put_progress(conn, body),
    do:
      conn |> put_req_header("content-type", "application/json") |> put("/koreader/syncs/progress", Jason.encode!(body))

  test "the partial MD5 samples the file as KOReader does", %{tmp_dir: tmp} do
    data = :crypto.strong_rand_bytes(20_000)
    path = Path.join(tmp, "sample.bin")
    File.write!(path, data)

    samples =
      for offset <- [0, 1024, 4096, 16_384],
          offset < byte_size(data),
          do: binary_part(data, offset, min(1024, byte_size(data) - offset))

    assert Koreader.partial_md5(path) == Base.encode16(:crypto.hash(:md5, samples), case: :lower)
  end

  test "signs in with an app password's MD5", %{conn: conn, bare: bare} do
    assert conn |> get("/koreader/users/auth") |> json_response(200) == %{"authorized" => "OK"}

    wrong = Base.encode16(:crypto.hash(:md5, "password1234"), case: :lower)

    assert bare
           |> put_req_header("x-auth-user", "koreader")
           |> put_req_header("x-auth-key", wrong)
           |> get("/koreader/users/auth")
           |> json_response(401)

    assert bare |> post("/koreader/users/create", %{}) |> json_response(403)
  end

  test "a comic syncs by page", %{conn: conn, user: user, comic: comic, comic_hash: hash} do
    assert conn |> get("/koreader/syncs/progress/#{hash}") |> json_response(200) == %{}

    body = %{document: hash, progress: "7", percentage: 0.35, device: "Kobo Libra", device_id: "ABC"}
    assert %{"document" => ^hash, "timestamp" => _} = conn |> put_progress(body) |> json_response(200)
    assert %{current_page: 6} = Library.get_progress(user.id, comic.id)

    assert %{"progress" => "7", "device" => "Kobo Libra", "device_id" => "ABC"} =
             conn |> get("/koreader/syncs/progress/#{hash}") |> json_response(200)

    assert conn |> put_progress(%{body | progress: "99"}) |> json_response(400)
  end

  test "an EPUB keeps KOReader's XPointer and gives Stashix's spot as a chapter",
       %{conn: conn, user: user, novel: novel, novel_hash: hash} do
    xpointer = "/body/DocFragment[2]/body/p[1]/text().4"
    body = %{document: hash, progress: xpointer, percentage: 0.6, device: "Kobo", device_id: "K1"}
    assert conn |> put_progress(body) |> json_response(200)

    assert %{progression: 0.6, locator: %{"koreader" => ^xpointer, "href" => "OEBPS/ch2.xhtml"}} =
             Library.get_progress(user.id, novel.id)

    assert %{"progress" => ^xpointer, "percentage" => 0.6} =
             conn |> get("/koreader/syncs/progress/#{hash}") |> json_response(200)

    # Read on in Stashix (no XPointer): KOReader gets the chapter's start.
    {:ok, _} =
      Library.update_progress(Library.Access.all(), user.id, novel.id, 3,
        progression: 0.2,
        locator: %{"type" => "epub", "cfi" => "epubcfi(/6/2!/4/2)", "href" => "OEBPS/ch1.xhtml"}
      )

    assert %{"progress" => "/body/DocFragment[1].0", "percentage" => 0.2} =
             conn |> get("/koreader/syncs/progress/#{hash}") |> json_response(200)
  end

  test "an unknown document is not found", %{conn: conn} do
    body = %{document: String.duplicate("0", 32), progress: "1", percentage: 0.1, device: "K", device_id: "1"}
    assert conn |> put_progress(body) |> json_response(404)
  end

  test "a changed file gets a new hash", %{conn: conn, comic: comic, comic_hash: old, tmp_dir: tmp} do
    path = Path.join(tmp, "strip.cbz")
    File.write!(path, :crypto.strong_rand_bytes(5000))
    file = Repo.get_by!(BookFile, book_id: comic.id)
    Repo.update!(Ecto.Changeset.change(file, file_hash: Stashix.Scanner.compute_hash(path, 5000)))
    new = Koreader.partial_md5(path)

    assert conn |> get("/koreader/syncs/progress/#{old}") |> json_response(200)
    body = %{document: new, progress: "2", percentage: 0.1, device: "K", device_id: "1"}
    assert conn |> put_progress(body) |> json_response(200)
    assert conn |> put_progress(%{body | document: old}) |> json_response(404)
  end
end
