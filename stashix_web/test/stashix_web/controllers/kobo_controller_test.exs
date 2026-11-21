# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.KoboControllerTest do
  use StashixWeb.ConnCase, async: false

  import Ecto.Query

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.{Book, BookFile}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    previous = Application.fetch_env(:stashix, :kepubify)
    Application.put_env(:stashix, :kepubify, nil)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:stashix, :kepubify, value)
        :error -> Application.delete_env(:stashix, :kepubify)
      end
    end)

    {:ok, user} = Accounts.create_user(%{email: "kobo@example.com", username: "kobo", password: "password1234"})
    {:ok, _app, token} = Accounts.create_app_password(user, "Libra")
    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp, kind: :books})

    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, can_download: true})

    novel = add_book(lib, tmp, "Novel", :epub)
    _comic = add_book(lib, tmp, "Strip", :cbz)

    %{user: user, token: token, lib: lib, novel: novel, tmp_dir: tmp, base: "/kobo/#{token}"}
  end

  defp add_book(lib, tmp, title, format) do
    {:ok, book} =
      Library.create_book(%{
        title: title,
        library_id: lib.id,
        type: "standalone",
        summary: "About #{title}",
        language: "en"
      })

    path = Path.join(tmp, "#{title}-#{System.unique_integer([:positive])}.#{format}")
    File.write!(path, "data of #{title}")

    Repo.insert!(%BookFile{
      book_id: book.id,
      path: path,
      format: format,
      file_size: 12,
      file_hash: "hash-#{title}"
    })

    book
  end

  defp sync(conn, base, token \\ nil) do
    conn = if token, do: put_req_header(conn, "x-kobo-synctoken", token), else: conn
    conn = get(conn, base <> "/v1/library/sync")
    [token] = get_resp_header(conn, "x-kobo-synctoken")
    {json_response(conn, 200), token, get_resp_header(conn, "x-kobo-sync") == ["continue"]}
  end

  defp touch(book, seconds) do
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(seconds) |> NaiveDateTime.truncate(:second)
    Repo.update_all(from(b in Book, where: b.id == ^book.id), set: [updated_at: at])
  end

  test "a wrong token is refused", %{conn: conn} do
    assert conn |> get("/kobo/stx_nope/v1/library/sync") |> response(401)
  end

  test "initialization points the device's images here", %{conn: conn, base: base, token: token} do
    resources = conn |> get(base <> "/v1/initialization") |> json_response(200) |> Map.fetch!("Resources")

    assert resources["image_url_template"] ==
             "http://www.example.com/kobo/#{token}/v1/books/{ImageId}/thumbnail/{Width}/{Height}/false/image.jpg"

    assert resources["library_sync"]
  end

  test "the first sync sends every EPUB book, the next only changes", %{
    conn: conn,
    base: base,
    novel: novel,
    token: token
  } do
    {[item], sync_token, false} = sync(conn, base)

    assert %{"NewEntitlement" => %{"BookEntitlement" => entitlement, "BookMetadata" => meta, "ReadingState" => state}} =
             item

    assert entitlement["Id"] == novel.id and entitlement["IsRemoved"] == false
    assert meta["Title"] == "Novel"
    assert meta["Description"] == "About Novel"

    assert [%{"Format" => "EPUB3", "Url" => url}] = meta["DownloadUrls"]
    assert url == "http://www.example.com/kobo/#{token}/v1/books/#{novel.id}/file/epub?convert_kepub=false"
    assert state["StatusInfo"]["Status"] == "ReadyToRead"

    assert {[], sync_token, false} = sync(conn, base, sync_token)

    touch(novel, 60)
    {items, sync_token, false} = sync(conn, base, sync_token)
    assert [%{"NewEntitlement" => _}, %{"ChangedProductMetadata" => %{"EntitlementId" => id}}] = items
    assert id == novel.id

    Repo.update_all(from(b in Book, where: b.id == ^novel.id), set: [deleted_at: NaiveDateTime.utc_now()])
    {[removed], _token, false} = sync(conn, base, sync_token)
    assert %{"ChangedEntitlement" => %{"BookEntitlement" => %{"Id" => ^id, "IsRemoved" => true}}} = removed
  end

  test "a device without a token gets everything again", %{conn: conn, base: base} do
    {[_], _token, false} = sync(conn, base)
    {[_], _token, false} = sync(conn, base)
  end

  test "big libraries sync in batches", %{conn: conn, base: base, lib: lib, tmp_dir: tmp} do
    for n <- 1..104, do: add_book(lib, tmp, "Book #{n}", :epub)

    {first, sync_token, true} = sync(conn, base)
    assert length(first) == 100
    {rest, sync_token, false} = sync(conn, base, sync_token)
    assert length(rest) == 5
    assert {[], _, false} = sync(conn, base, sync_token)
  end

  test "books the user may not download are left out", %{conn: conn, base: base, user: user, lib: lib} do
    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, can_download: false})

    assert {[], _, false} = sync(conn, base)
  end

  test "reading state goes both ways", %{conn: conn, base: base, user: user, novel: novel} do
    {_, sync_token, false} = sync(conn, base)

    update = %{
      "ReadingStates" => [
        %{
          "EntitlementId" => novel.id,
          "LastModified" => DateTime.utc_now() |> DateTime.add(-10) |> DateTime.to_iso8601(),
          "CurrentBookmark" => %{
            "ProgressPercent" => 42,
            "ContentSourceProgressPercent" => 30,
            "Location" => %{"Source" => "OEBPS/ch2.xhtml", "Type" => "KoboSpan", "Value" => "kobo.12.3"}
          },
          "StatusInfo" => %{"Status" => "Reading"}
        }
      ]
    }

    result = conn |> put(base <> "/v1/library/#{novel.id}/state", update) |> json_response(200)
    assert result["RequestResult"] == "Success"

    assert %{progression: 0.42, locator: %{"href" => "OEBPS/ch2.xhtml", "kobo_span" => "kobo.12.3"}} =
             Library.get_progress(user.id, novel.id)

    [state] = conn |> get(base <> "/v1/library/#{novel.id}/state") |> json_response(200)

    assert %{"ProgressPercent" => 42.0, "Location" => %{"Value" => "kobo.12.3", "Source" => "OEBPS/ch2.xhtml"}} =
             state["CurrentBookmark"]

    assert state["StatusInfo"]["Status"] == "Reading"

    # An older state from the device doesn't win.
    old = put_in(update, ["ReadingStates", Access.at(0), "LastModified"], "2020-01-01T00:00:00Z")
    old = put_in(old, ["ReadingStates", Access.at(0), "CurrentBookmark", "ProgressPercent"], 5)
    assert conn |> put(base <> "/v1/library/#{novel.id}/state", old) |> json_response(200)
    assert %{progression: 0.42} = Library.get_progress(user.id, novel.id)

    # Read on in Stashix: the next sync tells the device.
    Process.sleep(1100)
    {:ok, _} = Library.update_progress(Library.Access.all(), user.id, novel.id, 0, progression: 0.8)
    {[changed], _, false} = sync(conn, base, sync_token)

    assert %{"ChangedReadingState" => %{"ReadingState" => %{"CurrentBookmark" => %{"ProgressPercent" => 80.0}}}} =
             changed
  end

  test "books download as EPUB, or KEPUB through kepubify", %{conn: conn, base: base, novel: novel, tmp_dir: tmp} do
    assert conn |> get(base <> "/v1/books/#{novel.id}/file/epub?convert_kepub=false") |> response(200) ==
             "data of Novel"

    fake = Path.join(tmp, "kepubify")
    File.write!(fake, "#!/bin/sh\n# kepubify -o OUT IN\n(echo kepub; cat \"$3\") > \"$2\"\n")
    File.chmod!(fake, 0o755)
    Application.put_env(:stashix, :kepubify, fake)

    {[item], _, false} = sync(conn, base)
    assert [%{"Format" => "KEPUB", "Url" => url}] = item["NewEntitlement"]["BookMetadata"]["DownloadUrls"]
    assert url =~ "convert_kepub=true"

    conn = get(conn, base <> "/v1/books/#{novel.id}/file/epub?convert_kepub=true")
    assert response(conn, 200) == "kepub\ndata of Novel"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ".kepub.epub"
  end

  test "store calls Stashix has no part in get an empty answer", %{conn: conn, base: base} do
    assert conn |> get(base <> "/v1/user/wishlist") |> json_response(200) == %{}

    assert conn |> post(base <> "/v1/auth/device", %{"UserKey" => "k"}) |> json_response(200) |> Map.get("UserKey") ==
             "k"
  end
end
