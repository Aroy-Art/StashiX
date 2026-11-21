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

  describe "shelves" do
    alias Stashix.Collections

    setup %{user: user, novel: novel} do
      {:ok, c} = Collections.create(user, %{name: "Night reading"})
      {:ok, _} = Collections.add(user, Library.Access.for_user(user), c, {:book, novel.id})
      %{collection: c}
    end

    defp tags(items), do: Enum.filter(items, &(Map.keys(&1) |> hd() |> String.ends_with?("Tag")))

    test "the user's collections go to the device as shelves, and follow changes", ctx do
      %{conn: conn, base: base, user: user, collection: c, novel: novel} = ctx
      {items, token, false} = sync(conn, base)

      assert [%{"NewTag" => %{"Tag" => tag}}] = tags(items)
      assert %{"Id" => id, "Name" => "Night reading", "Type" => "UserTag", "Items" => [item]} = tag
      assert id == c.id
      assert item == %{"RevisionId" => novel.id, "Type" => "ProductRevisionTagItem"}

      assert {[], token, false} = sync(conn, base, token)

      {:ok, c} = Collections.update(user, c, %{name: "Late reading"})
      {items, token, false} = sync(conn, base, token)
      assert [%{"ChangedTag" => %{"Tag" => %{"Name" => "Late reading"}}}] = tags(items)

      {:ok, _} = Collections.delete(user, c)
      {items, _token, false} = sync(conn, base, token)
      assert [%{"DeletedTag" => %{"Tag" => %{"Id" => ^id}}}] = tags(items)
    end

    test "others' shared collections are not shelves", %{conn: conn, base: base, lib: lib, novel: novel} do
      {:ok, other} = Accounts.create_user(%{email: "sh@example.com", username: "sharer", password: "password1234"})
      {:ok, _} = Library.set_library_permission(%{user_id: other.id, library_id: lib.id, can_read: true})
      {:ok, c} = Collections.create(other, %{name: "Theirs", shared: true})
      {:ok, _} = Collections.add(other, Library.Access.for_user(other), c, {:book, novel.id})

      {items, _, false} = sync(conn, base)
      assert [%{"NewTag" => %{"Tag" => %{"Name" => "Night reading"}}}] = tags(items)
    end

    test "shelves made and changed on the device become collections", ctx do
      %{conn: conn, base: base, user: user, novel: novel} = ctx
      {_, token, false} = sync(conn, base)
      item = %{"RevisionId" => novel.id, "Type" => "ProductRevisionTagItem"}

      id =
        conn |> post(base <> "/v1/library/tags", %{"Name" => "On the train", "Items" => [item]}) |> json_response(201)

      {:ok, c} = Collections.get(user, Library.Access.for_user(user), id)
      assert c.name == "On the train"
      assert Collections.containing(user, {:book, novel.id})[c.id] == :direct

      # The device has it as it is: the next sync doesn't send it back.
      assert {[], token, false} = sync(conn, base, token)

      assert conn |> put(base <> "/v1/library/tags/#{id}", %{"Name" => "Commute"}) |> response(200)
      assert {:ok, %{name: "Commute"}} = Collections.get(user, Library.Access.for_user(user), id)

      assert conn |> post(base <> "/v1/library/tags/#{id}/items/delete", %{"Items" => [item]}) |> response(200)
      assert Collections.containing(user, {:book, novel.id})[c.id] == nil
      assert conn |> post(base <> "/v1/library/tags/#{id}/items", %{"Items" => [item]}) |> response(201)
      assert Collections.containing(user, {:book, novel.id})[c.id] == :direct

      assert conn |> delete(base <> "/v1/library/tags/#{id}") |> response(200)
      assert {:error, :not_found} = Collections.get(user, Library.Access.for_user(user), id)
      assert {[], _token, false} = sync(conn, base, token)
    end

    test "a shelf of only Kobo books stays with Kobo", %{conn: conn, base: base, user: user} do
      Application.put_env(:stashix, :kobo_proxy, true)
      on_exit(fn -> Application.put_env(:stashix, :kobo_proxy, false) end)
      store_book = Ecto.UUID.generate()

      Req.Test.stub(Stashix.Kobo.Store, fn store ->
        assert store.request_path == "/v1/library/tags"
        store |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(201, ~s("kobo-tag"))
      end)

      body = %{"Name" => "Bought", "Items" => [%{"RevisionId" => store_book, "Type" => "ProductRevisionTagItem"}]}
      assert conn |> post(base <> "/v1/library/tags", body) |> json_response(201) == "kobo-tag"
      refute Enum.any?(Collections.own(user), &(&1.name == "Bought"))
    end
  end

  describe "with the Kobo store proxy" do
    setup do
      Application.put_env(:stashix, :kobo_proxy, true)
      on_exit(fn -> Application.put_env(:stashix, :kobo_proxy, false) end)
    end

    defp stub_store(fun), do: Req.Test.stub(Stashix.Kobo.Store, fun)

    defp kobo(conn, status, body, headers \\ []) do
      headers
      |> Enum.reduce(conn, fn {k, v}, conn -> Plug.Conn.put_resp_header(conn, k, v) end)
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end

    test "start-up resources come from Kobo, with images pointed here", %{conn: conn, base: base, token: token} do
      stub_store(fn store ->
        assert store.request_path == "/v1/initialization"
        assert Plug.Conn.get_req_header(store, "authorization") == ["Bearer device"]

        kobo(store, 200, %{
          "Resources" => %{"library_sync" => "https://storeapi.kobo.com/v1/library/sync", "new_thing" => "x"}
        })
      end)

      resources =
        conn
        |> put_req_header("authorization", "Bearer device")
        |> get(base <> "/v1/initialization")
        |> json_response(200)
        |> Map.fetch!("Resources")

      assert resources["new_thing"] == "x"
      assert resources["image_url_template"] =~ "/kobo/#{token}/v1/books/{ImageId}/thumbnail"

      # Kobo signing the device out is passed on.
      stub_store(&kobo(&1, 401, %{"error" => "expired"}))
      assert conn |> get(base <> "/v1/initialization") |> response(401)

      # Kobo out of reach: the kept copy.
      stub_store(&Req.Test.transport_error(&1, :econnrefused))
      assert conn |> get(base <> "/v1/initialization") |> json_response(200) |> get_in(["Resources", "library_sync"])
    end

    test "other calls go to Kobo with their path, query and body", %{conn: conn, base: base} do
      stub_store(fn store ->
        {:ok, body, store} = Plug.Conn.read_body(store)
        assert store.method == "PUT"
        assert store.request_path == "/v1/user/wishlist"
        assert store.query_string == "page=2"
        assert Jason.decode!(body) == %{"Items" => [1]}
        assert Plug.Conn.get_req_header(store, "x-kobo-deviceid") == ["dev"]
        kobo(store, 201, %{"ok" => true}, [{"x-kobo-recent-reads", "1"}])
      end)

      conn =
        conn
        |> put_req_header("x-kobo-deviceid", "dev")
        |> put_req_header("content-type", "application/json")
        |> put(base <> "/v1/user/wishlist?page=2", Jason.encode!(%{"Items" => [1]}))

      assert json_response(conn, 201) == %{"ok" => true}
      assert get_resp_header(conn, "x-kobo-recent-reads") == ["1"]
    end

    test "the library sync adds Kobo's books after Stashix's", %{conn: conn, base: base, novel: novel} do
      stub_store(fn store ->
        assert Plug.Conn.get_req_header(store, "x-kobo-synctoken") == []
        kobo(store, 200, [%{"NewEntitlement" => %{"From" => "kobo"}}], [{"x-kobo-synctoken", "kobo-1"}])
      end)

      {[ours, theirs], sync_token, false} = sync(conn, base)
      assert ours["NewEntitlement"]["BookEntitlement"]["Id"] == novel.id
      assert theirs == %{"NewEntitlement" => %{"From" => "kobo"}}

      # Kobo gets its own token back, and may ask to go on: Stashix's part
      # is not sent again meanwhile.
      stub_store(fn store ->
        assert Plug.Conn.get_req_header(store, "x-kobo-synctoken") == ["kobo-1"]
        kobo(store, 200, [%{"Kobo" => 2}], [{"x-kobo-synctoken", "kobo-2"}, {"x-kobo-sync", "continue"}])
      end)

      touch(novel, 60)
      {items, sync_token, true} = sync(conn, base, sync_token)
      assert [%{"NewEntitlement" => _}, %{"ChangedProductMetadata" => _}, %{"Kobo" => 2}] = items

      stub_store(fn store ->
        assert Plug.Conn.get_req_header(store, "x-kobo-synctoken") == ["kobo-2"]
        kobo(store, 200, [%{"Kobo" => 3}], [{"x-kobo-synctoken", "kobo-3"}])
      end)

      assert {[%{"Kobo" => 3}], _token, false} = sync(conn, base, sync_token)
    end

    test "a book bought from Kobo is Kobo's", %{conn: conn, base: base, novel: novel} do
      store_id = Ecto.UUID.generate()

      stub_store(fn store ->
        assert store.request_path == "/v1/library/#{store_id}/metadata"
        kobo(store, 200, [%{"Title" => "Bought"}])
      end)

      assert [%{"Title" => "Bought"}] = conn |> get(base <> "/v1/library/#{store_id}/metadata") |> json_response(200)

      conn2 = get(conn, base <> "/v1/books/#{store_id}/thumbnail/300/400/false/image.jpg")
      assert redirected_to(conn2) == "https://cdn.kobo.com/book-images/#{store_id}/300/400/false/image.jpg"

      # Stashix's own books never go to Kobo.
      stub_store(fn _ -> flunk("sent to Kobo") end)
      assert [%{"Title" => "Novel"}] = conn |> get(base <> "/v1/library/#{novel.id}/metadata") |> json_response(200)
    end
  end
end
