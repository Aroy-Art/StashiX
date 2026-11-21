# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.KoboController do
  @moduledoc """
  Kobo sync: enough of the Kobo store API for a Kobo eReader to sync books
  and reading progress with Stashix, as Calibre-Web and Komga do.

  On the device, `api_endpoint` in `.kobo/Kobo/Kobo eReader.conf` is set to
  `https://<stashix>/kobo/<app password>` (`StashixWeb.Plugs.KoboAuth`).
  The device then asks here for its library (`sync/2`, in batches, carrying
  a sync token), each book's metadata and reading state, the books
  themselves (`download/2`, KEPUB when `kepubify` is installed) and covers.

  Everything else goes on to Kobo's own store (`Stashix.Kobo.Store`), with
  the device's Kobo credentials: the shop, wishlists, and the books bought
  from Kobo, whose sync is added after Stashix's and whose metadata, state
  and covers come from Kobo. With the proxy off those calls get an empty
  answer and Kobo purchases don't sync.

  Shelves are the user's own collections (`Stashix.Collections`), with the
  books of each the device has; shelves made or changed on the device
  change the collections back (`create_tag/2` and friends).

  Reading state goes both ways: the device's spot (chapter, Kobo span and
  how far through) is saved as Stashix progress, and progress from the web
  readers and other apps goes back to the device on the next sync.
  """
  use StashixWeb, :controller

  import Ecto.Query

  alias Stashix.{Kobo, Library, Repo}
  alias Stashix.Kobo.Store
  alias Stashix.Library.{Access, Book, ReadingProgress}

  @sync_limit 100
  @dummy_id "00000000-0000-0000-0000-000000000001"
  # The store's own resource URLs (from Komga's Kobo support), which the
  # device needs at start-up; the image ones are pointed here.
  @resources_path Path.expand("../../../priv/kobo/resources.json", __DIR__)
  @external_resource @resources_path
  @resources @resources_path |> File.read!() |> Jason.decode!()

  ## Device setup

  # Kobo's resources when the store answers (it may sign the device out with
  # a 401), the copy kept here otherwise; the image ones point here.
  def initialization(conn, %{"token" => token}) do
    images = "#{base_url(conn)}/kobo/#{token}/v1/books/{ImageId}/thumbnail"

    case store_resources(conn) do
      {:unauthorized, response} -> send_store_response(conn, response)
      resources -> send_resources(conn, resources, images)
    end
  end

  defp store_resources(conn) do
    with true <- Store.enabled?(),
         {:ok, %{status: 200, body: body}} <- forward(conn),
         {:ok, %{"Resources" => %{} = resources}} <- Jason.decode(body) do
      resources
    else
      {:ok, %{status: 401} = response} -> {:unauthorized, response}
      _ -> @resources
    end
  end

  defp send_resources(conn, resources, images) do
    resources =
      Map.merge(resources, %{
        "image_host" => base_url(conn),
        "image_url_template" => images <> "/{Width}/{Height}/false/image.jpg",
        "image_url_quality_template" => images <> "/{Width}/{Height}/{Quality}/{IsGreyscale}/image.jpg"
      })

    conn
    |> put_resp_header("x-kobo-apitoken", "e30=")
    |> json(%{"Resources" => resources})
  end

  # The device asks for store tokens: Kobo's when the store answers. Stashix
  # signs it in by the URL, so made-up ones do otherwise.
  def auth_device(conn, params) do
    case Store.enabled?() && forward(conn) do
      {:ok, %{status: 200} = response} -> send_store_response(conn, response)
      _ -> fake_auth(conn, params)
    end
  end

  defp fake_auth(conn, params) do
    json(conn, %{
      "AccessToken" => random_token(),
      "RefreshToken" => random_token(),
      "TokenType" => "Bearer",
      "TrackingId" => Ecto.UUID.generate(),
      "UserKey" => params["UserKey"] || ""
    })
  end

  @doc "Store calls Stashix does not answer for: on to Kobo, or an empty answer."
  def other(conn, _params), do: proxy(conn)

  # Kobo's answer to this request as it is, or `{}` when the proxy is off
  # or the store can't be reached.
  defp proxy(conn) do
    case Store.enabled?() && forward(conn) do
      {:ok, response} -> send_store_response(conn, response)
      _ -> json(conn, %{})
    end
  end

  defp forward(conn, extra_headers \\ []) do
    ["kobo", _token | rest] = conn.path_info

    Store.request(
      method(conn),
      "/" <> Enum.join(rest, "/"),
      conn.query_string,
      conn.req_headers,
      request_body(conn),
      extra_headers
    )
  end

  defp method(conn), do: conn.method |> String.downcase() |> String.to_existing_atom()

  # JSON bodies were parsed on the way in: sent on as JSON again. Others
  # are still unread.
  defp request_body(%{method: method}) when method in ["GET", "HEAD", "DELETE"], do: nil

  defp request_body(conn) do
    if conn.body_params == %{} or match?(%Plug.Conn.Unfetched{}, conn.body_params) do
      case Plug.Conn.read_body(conn) do
        {:ok, body, _conn} -> body
        _ -> ""
      end
    else
      Jason.encode!(conn.body_params)
    end
  end

  defp send_store_response(conn, %{status: status, headers: headers, body: body, content_type: type}) do
    headers
    |> Enum.reduce(conn, fn {name, value}, conn -> put_resp_header(conn, name, value) end)
    |> put_resp_content_type(type, nil)
    |> send_resp(status, body)
  end

  ## Library sync

  @doc """
  The device's library, as changes since its last sync: new books, changed
  ones, removed ones and reading states, at most #{@sync_limit} at a time
  (`x-kobo-sync: continue` asks for the rest), then Kobo's own sync of the
  books bought there. The sync token holds when the last complete sync
  started (`since`), mid-way when this one did (`round`), Kobo's own token
  (`kobo`), and whether only Kobo's part is left (`phase`).
  """
  def sync(conn, _params) do
    token = read_sync_token(conn)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    round = parse_time(token["round"]) || now

    {results, more?} = if token["phase"] == "kobo", do: {[], false}, else: library_sync(conn, token)
    {kobo_results, kobo_token, kobo_more?} = if more?, do: {[], token["kobo"], false}, else: store_sync(conn, token)

    next_token =
      cond do
        more? -> %{"since" => token["since"], "round" => iso(round), "kobo" => token["kobo"]}
        kobo_more? -> %{"since" => token["since"], "round" => iso(round), "kobo" => kobo_token, "phase" => "kobo"}
        true -> %{"since" => iso(round), "kobo" => kobo_token}
      end

    conn
    |> put_resp_header("x-kobo-synctoken", next_token |> Jason.encode!() |> Base.encode64())
    |> then(&if(more? or kobo_more?, do: put_resp_header(&1, "x-kobo-sync", "continue"), else: &1))
    |> json(results ++ kobo_results)
  end

  # Kobo's sync of the store's books, with Kobo's own token.
  defp store_sync(conn, token) do
    extra = if is_binary(token["kobo"]), do: [{"x-kobo-synctoken", token["kobo"]}], else: []

    with true <- Store.enabled?(),
         {:ok, %{status: 200, body: body, headers: headers}} <- forward(conn, extra),
         {:ok, results} when is_list(results) <- Jason.decode(body) do
      header = &Enum.find_value(headers, fn {name, value} -> name == &1 && value end)
      {results, header.("x-kobo-synctoken") || token["kobo"], header.("x-kobo-sync") == "continue"}
    else
      _ -> {[], token["kobo"], false}
    end
  end

  defp library_sync(conn, token) do
    %{access: access, app_password: app_password, current_user: user} = conn.assigns
    since = parse_time(token["since"])

    # A device without a token (new, or reset) starts over.
    if is_nil(since) and is_nil(token["round"]) do
      Kobo.mark_removed(app_password.id, Map.keys(Kobo.synced(app_password.id)))
      Kobo.forget_shelves(app_password.id, :all)
    end

    current = Map.new(Kobo.books(access), &{&1.id, &1.modified})
    synced = Kobo.synced(app_password.id)

    new = current |> Map.keys() |> Enum.reject(&Map.has_key?(synced, &1)) |> Enum.sort()

    changed =
      synced
      |> Enum.filter(fn {id, at} -> current[id] && NaiveDateTime.compare(current[id], at) == :gt end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    removed = synced |> Map.keys() |> Enum.reject(&Map.has_key?(current, &1)) |> Enum.sort()
    states = if since, do: changed_states(user.id, Map.keys(synced) -- (removed ++ changed), since), else: []

    {new_now, rest} = Enum.split(new, @sync_limit)
    {changed_now, rest2} = Enum.split(changed, @sync_limit - length(new_now))
    {removed_now, rest3} = Enum.split(removed, @sync_limit - length(new_now) - length(changed_now))
    {states_now, rest4} = Enum.split(states, @sync_limit - length(new_now) - length(changed_now) - length(removed_now))
    more? = Enum.any?([rest, rest2, rest3, rest4], &(&1 != []))

    books = Map.new(Kobo.load_books(new_now ++ changed_now), &{&1.id, &1})
    progress = progress_map(user.id, new_now ++ changed_now ++ states_now)
    urls = urls(conn)

    results =
      Enum.map(new_now, &new_entitlement(books[&1], current[&1], progress[&1], urls)) ++
        Enum.flat_map(changed_now, fn id ->
          [
            new_entitlement(books[id], current[id], progress[id], urls),
            %{"ChangedProductMetadata" => book_metadata(books[id], urls)}
          ] ++ List.wrap(progress[id] && changed_state(books[id], progress[id]))
        end) ++
        Enum.map(removed_now, &removed_entitlement/1) ++
        Enum.map(states_now, &changed_state(&1, progress[&1]))

    Kobo.mark_synced(app_password.id, new_now ++ changed_now)
    Kobo.mark_removed(app_password.id, removed_now)

    # Shelves once the books are all there, so their items are on the device.
    shelves = if more?, do: [], else: shelf_changes(conn, Map.keys(current))

    {results ++ shelves, more?}
  end

  # The user's own collections as shelves (not others' shared ones: edits on
  # the device couldn't be kept). A shelf holds the collection's books that
  # the device has; it is sent when new, when its name or books change, and
  # deleted when the collection is gone.
  defp shelf_changes(conn, device_book_ids) do
    %{access: access, app_password: app_password, current_user: user} = conn.assigns
    held = MapSet.new(device_book_ids)
    own = Stashix.Collections.own(user)
    expanded = own |> Enum.map(& &1.id) |> Stashix.Collections.expanded_ids(access)
    synced = Kobo.synced_shelves(app_password.id)

    shelves =
      for c <- own do
        items = expanded |> Map.get(c.id, []) |> Enum.filter(&MapSet.member?(held, &1))
        {c, items, Kobo.shelf_hash(c.name, items)}
      end

    sent =
      for {c, items, hash} <- shelves, synced[c.id] != hash do
        kind = if Map.has_key?(synced, c.id), do: "ChangedTag", else: "NewTag"
        {%{kind => %{"Tag" => tag(c, items)}}, {c.id, hash}}
      end

    gone = Map.keys(synced) -- Enum.map(own, & &1.id)
    Kobo.mark_shelves(app_password.id, Enum.map(sent, &elem(&1, 1)))
    Kobo.forget_shelves(app_password.id, gone)

    Enum.map(sent, &elem(&1, 0)) ++
      Enum.map(gone, &%{"DeletedTag" => %{"Tag" => %{"Id" => &1, "LastModified" => iso(DateTime.utc_now())}}})
  end

  defp tag(c, items) do
    %{
      "Created" => iso(c.inserted_at),
      "Id" => c.id,
      "Items" => Enum.map(items, &%{"RevisionId" => &1, "Type" => "ProductRevisionTagItem"}),
      "LastModified" => iso(c.updated_at),
      "Name" => c.name,
      "Type" => "UserTag"
    }
  end

  ## Shelves edited on the device

  @doc """
  A shelf made on the device. It becomes a collection (or joins the one of
  that name) unless it holds only books bought from Kobo: those shelves stay
  with Kobo. Answers with the collection's id, which the device uses from
  then on.
  """
  def create_tag(conn, %{"Name" => name} = params) when is_binary(name) and name != "" do
    %{current_user: user, access: access} = conn.assigns
    {ours, theirs} = params |> tag_items() |> Enum.split_with(&ours?/1)

    if ours == [] and theirs != [] and Store.enabled?() do
      proxy(conn)
    else
      collection =
        Enum.find(Stashix.Collections.own(user), &(String.downcase(&1.name) == String.downcase(String.trim(name)))) ||
          case Stashix.Collections.create(user, %{name: name}) do
            {:ok, c} -> c
            {:error, _} -> nil
          end

      if collection do
        Enum.each(ours, &Stashix.Collections.add(user, access, collection, {:book, &1}))
        device_saw(conn, collection)
        conn |> put_status(:created) |> json(collection.id)
      else
        conn |> put_status(:bad_request) |> json(%{error: "invalid shelf name"})
      end
    end
  end

  def create_tag(conn, _params), do: conn |> put_status(:bad_request) |> json(%{error: "Name is required"})

  @doc "Renames (PUT) or deletes (DELETE) a shelf that is a collection of the user's."
  def update_tag(conn, %{"tag_id" => tag_id} = params) do
    with_own_collection(conn, tag_id, fn c ->
      user = conn.assigns.current_user

      case conn.method do
        "DELETE" ->
          Stashix.Collections.delete(user, c)
          Kobo.forget_shelves(conn.assigns.app_password.id, [c.id])
          send_resp(conn, 200, " ")

        _ ->
          case Stashix.Collections.update(user, c, %{name: params["Name"]}) do
            {:ok, c} ->
              device_saw(conn, c)
              send_resp(conn, 200, " ")

            {:error, _} ->
              conn |> put_status(:bad_request) |> json(%{error: "invalid shelf name"})
          end
      end
    end)
  end

  @doc "Books added to a shelf on the device. Books bought from Kobo can't join a Stashix collection."
  def add_tag_items(conn, %{"tag_id" => tag_id} = params) do
    with_own_collection(conn, tag_id, fn c ->
      %{current_user: user, access: access} = conn.assigns

      params
      |> tag_items()
      |> Enum.filter(&ours?/1)
      |> Enum.each(&Stashix.Collections.add(user, access, c, {:book, &1}))

      device_saw(conn, c)
      send_resp(conn, 201, "")
    end)
  end

  @doc "Books taken off a shelf on the device; a book there through its series takes the series apart."
  def remove_tag_items(conn, %{"tag_id" => tag_id} = params) do
    with_own_collection(conn, tag_id, fn c ->
      %{current_user: user, access: access} = conn.assigns
      params |> tag_items() |> Enum.filter(&ours?/1) |> Enum.each(&Stashix.Collections.remove_book(user, access, c, &1))
      device_saw(conn, c)
      send_resp(conn, 200, "")
    end)
  end

  # A shelf the user owns as a collection; others go on to Kobo.
  defp with_own_collection(conn, tag_id, fun) do
    %{current_user: user, access: access} = conn.assigns

    case Stashix.Collections.get(user, access, tag_id) do
      {:ok, c} ->
        if Stashix.Collections.owner?(c, user),
          do: fun.(c),
          else: conn |> put_status(:forbidden) |> json(%{error: "not yours"})

      {:error, :not_found} ->
        if Store.enabled?(), do: proxy(conn), else: conn |> put_status(:not_found) |> json(%{error: "no such shelf"})
    end
  end

  defp tag_items(%{"Items" => items}) when is_list(items) do
    for %{"Type" => "ProductRevisionTagItem", "RevisionId" => id} <- items, is_binary(id), do: id
  end

  defp tag_items(_params), do: []

  # The device already has the shelf as it now is: no need to send it back.
  defp device_saw(conn, c) do
    %{access: access, app_password: app_password} = conn.assigns
    held = MapSet.new(Map.keys(Kobo.synced(app_password.id)))
    c = Repo.reload!(c)

    items =
      [c.id] |> Stashix.Collections.expanded_ids(access) |> Map.get(c.id, []) |> Enum.filter(&MapSet.member?(held, &1))

    Kobo.mark_shelves(app_password.id, [{c.id, Kobo.shelf_hash(c.name, items)}])
  end

  # Books the device has whose progress changed since its last sync.
  defp changed_states(_user_id, [], _since), do: []

  defp changed_states(user_id, book_ids, since) do
    since = DateTime.to_naive(since)

    from(p in ReadingProgress,
      where: p.user_id == ^user_id and p.book_id in ^book_ids and p.updated_at > ^since,
      order_by: p.book_id,
      select: p.book_id
    )
    |> Repo.all()
  end

  defp progress_map(_user_id, []), do: %{}

  defp progress_map(user_id, book_ids) do
    from(p in ReadingProgress, where: p.user_id == ^user_id and p.book_id in ^book_ids)
    |> Repo.all()
    |> Map.new(&{&1.book_id, &1})
  end

  defp read_sync_token(conn) do
    with [raw] <- get_req_header(conn, "x-kobo-synctoken"),
         {:ok, json} <- Base.decode64(raw),
         {:ok, %{} = token} <- Jason.decode(json) do
      token
    else
      _ -> %{}
    end
  end

  ## One book

  def metadata(conn, %{"id" => id}) do
    with_book(conn, id, fn book -> json(conn, [book_metadata(book, urls(conn))]) end)
  end

  def state(conn, %{"id" => id}) do
    with_book(conn, id, fn book ->
      json(conn, [reading_state(book, Library.get_progress(conn.assigns.current_user.id, book.id))])
    end)
  end

  @doc "The device's reading state for a book, saved as progress unless Stashix has a newer one."
  def update_state(conn, %{"id" => id} = params), do: with_book(conn, id, &save_state(conn, &1, params))

  defp save_state(conn, book, params) do
    %{access: access, current_user: user} = conn.assigns

    result =
      with [%{} = state | _] <- params["ReadingStates"],
           {:ok, progression, locator} <- from_state(state) do
        at = parse_time(state["LastModified"])
        saved = Library.get_progress(user.id, book.id)

        if saved && at && NaiveDateTime.compare(DateTime.to_naive(at), saved.updated_at) == :lt do
          :ignored
        else
          page = (saved && saved.current_page) || 0
          opts = [progression: progression, locator: locator, at: at && DateTime.to_naive(at)]
          with {:ok, _} <- Library.update_progress(access, user.id, book.id, page, opts), do: :ok
        end
      else
        _ -> :error
      end

    {request, bookmark} =
      case result do
        :ok -> {"Success", "Success"}
        :ignored -> {"Success", "Ignored"}
        _ -> {"Failure", "Failure"}
      end

    json(conn, %{
      "RequestResult" => request,
      "UpdateResults" => [
        %{
          "EntitlementId" => book.id,
          "CurrentBookmarkResult" => %{"Result" => bookmark},
          "StatisticsResult" => %{"Result" => "Ignored"},
          "StatusInfoResult" => %{"Result" => bookmark}
        }
      ]
    })
  end

  # Kobo's bookmark: the chapter (Source), the Kobo span in it (Value), and
  # percentages of the chapter and the book.
  defp from_state(state) do
    bookmark = state["CurrentBookmark"] || %{}
    location = bookmark["Location"] || %{}
    status = get_in(state, ["StatusInfo", "Status"])

    progression =
      case {status, bookmark["ProgressPercent"]} do
        {"Finished", _} -> 1.0
        {_, p} when is_number(p) -> p |> max(0) |> min(100) |> Kernel./(100)
        {"ReadyToRead", _} -> 0.0
        _ -> nil
      end

    locator =
      %{
        "type" => "epub",
        "href" => string(location["Source"]),
        "kobo_span" => if(location["Type"] in ["KoboSpan", "kobospan"], do: string(location["Value"])),
        "kobo_chapter_progress" =>
          if(is_number(bookmark["ContentSourceProgressPercent"]), do: bookmark["ContentSourceProgressPercent"] / 100)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if progression, do: {:ok, progression, locator}, else: :error
  end

  ## Files

  @doc "The book for the device: KEPUB (converted if need be) when asked, else the EPUB."
  def download(conn, %{"id" => id} = params) do
    book = kobo_book!(conn, id)
    file = Kobo.epub(book)

    path =
      cond do
        is_nil(file) -> {:error, :no_epub}
        params["convert_kepub"] == "true" and not Kobo.kepub?(file) -> Kobo.kepub(file)
        true -> {:ok, file.path}
      end

    case path do
      {:ok, path} ->
        name = if Kobo.kepub?(file) or path != file.path, do: "#{id}.kepub.epub", else: "#{id}.epub"

        conn
        |> put_resp_content_type("application/epub+zip", nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{name}"))
        |> send_file(200, path)

      {:error, reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: inspect(reason)})
    end
  end

  # A store book's cover comes from Kobo's image server.
  def cover(conn, %{"id" => id, "width" => width} = params) do
    if ours?(id) or not Store.enabled?(),
      do: StashixWeb.BookController.cover(conn, %{"id" => id, "w" => width}),
      else: redirect(conn, external: Store.cover_url(id, width, params["height"]))
  end

  # A book of Stashix's, else one bought from Kobo (on to the store).
  defp with_book(conn, id, fun) do
    if ours?(id) or not Store.enabled?(), do: fun.(kobo_book!(conn, id)), else: proxy(conn)
  end

  # Kobo's store ids are UUIDs too: a book is ours when the library has it.
  defp ours?(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.exists?(from b in Book, where: b.id == ^id)
      :error -> false
    end
  end

  defp kobo_book!(conn, id) do
    if Ecto.UUID.cast(id) == :error, do: raise(Ecto.NoResultsError, queryable: Book)
    book = conn.assigns.access |> Library.get_book!(id)

    if Access.can_download?(conn.assigns.access, book.library_id),
      do: book |> Repo.preload([:series, :publishers, :files, credits: :creator]),
      else: raise(Ecto.NoResultsError, queryable: Book)
  end

  ## Shapes

  defp new_entitlement(book, modified, progress, urls) do
    %{
      "NewEntitlement" => %{
        "BookEntitlement" => entitlement(book.id, book.inserted_at, modified, false),
        "BookMetadata" => book_metadata(book, urls),
        "ReadingState" => reading_state(book, progress)
      }
    }
  end

  defp removed_entitlement(id) do
    now = NaiveDateTime.utc_now()

    %{
      "ChangedEntitlement" => %{
        "BookEntitlement" => entitlement(id, now, now, true),
        "BookMetadata" => %{
          "CoverImageId" => id,
          "CrossRevisionId" => id,
          "EntitlementId" => id,
          "RevisionId" => id,
          "WorkId" => id,
          "Title" => id
        }
      }
    }
  end

  defp entitlement(id, created, modified, removed?) do
    %{
      "Accessibility" => "Full",
      "ActivePeriod" => %{"From" => iso(DateTime.utc_now())},
      "Created" => iso(created),
      "CrossRevisionId" => id,
      "Id" => id,
      "IsHiddenFromArchive" => false,
      "IsLocked" => false,
      "IsRemoved" => removed?,
      "LastModified" => iso(modified),
      "OriginCategory" => "Imported",
      "RevisionId" => id,
      "Status" => "Active"
    }
  end

  defp book_metadata(book, urls) do
    authors = StashixWeb.Opds.authors(book)
    publisher = List.first(book.publishers || [])

    %{
      "Categories" => [@dummy_id],
      "ContributorRoles" => Enum.map(authors, &%{"Name" => &1}),
      "Contributors" => authors,
      "CoverImageId" => book.id,
      "CrossRevisionId" => book.id,
      "CurrentDisplayPrice" => %{"CurrencyCode" => "USD", "TotalAmount" => 0},
      "CurrentLoveDisplayPrice" => %{"TotalAmount" => 0},
      "Description" => book.summary,
      "DownloadUrls" => download_urls(book, urls),
      "EntitlementId" => book.id,
      "ExternalIds" => [],
      "Genre" => @dummy_id,
      "IsEligibleForKoboLove" => false,
      "IsInternetArchive" => false,
      "IsPreOrder" => false,
      "IsSocialEnabled" => true,
      "Isbn" => book.isbn,
      "Language" => String.slice(book.language || "en", 0, 2),
      "PhoneticPronunciations" => %{},
      "PublicationDate" => publication_date(book),
      "Publisher" => publisher && %{"Imprint" => "", "Name" => publisher.name},
      "RevisionId" => book.id,
      "Series" => series(book),
      "Title" => StashixWeb.Opds.entry_title(book),
      "WorkId" => book.id
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp download_urls(book, urls) do
    case Kobo.epub(book) do
      nil ->
        []

      file ->
        {format, convert?} =
          cond do
            Kobo.fixed_layout?(file) -> {"EPUB3FL", false}
            Kobo.kepub?(file) -> {"KEPUB", false}
            Kobo.kepubify?() -> {"KEPUB", true}
            true -> {"EPUB3", false}
          end

        [
          %{
            "DrmType" => "None",
            "Format" => format,
            "Size" => file.file_size,
            "Platform" => "Generic",
            "Url" => "#{urls.books}/#{book.id}/file/epub?convert_kepub=#{convert?}"
          }
        ]
    end
  end

  defp series(%{series: %{name: name} = series} = book) when is_binary(name) do
    number = book.issue_number && Decimal.to_float(book.issue_number)

    %{
      "Id" => series.id,
      "Name" => name,
      "Number" => (book.issue_number && Stashix.Formatters.format_issue_number(book.issue_number)) || "",
      "NumberFloat" => number || 0.0
    }
  end

  defp series(_book), do: nil

  defp publication_date(%{cover_date: %Date{} = d}), do: iso(DateTime.new!(d, ~T[00:00:00]))
  defp publication_date(%{year: y}) when is_integer(y), do: iso(DateTime.new!(Date.new!(y, 1, 1), ~T[00:00:00]))
  defp publication_date(_book), do: nil

  defp changed_state(book_or_id, progress),
    do: %{"ChangedReadingState" => %{"ReadingState" => reading_state(book_or_id, progress)}}

  # Where the user is, for the device: from Kobo's own bookmark when it
  # saved last, else the chapter and share of the book other readers left.
  defp reading_state(book_or_id, nil) do
    {id, created} = id_and_created(book_or_id)
    at = iso(created)

    %{
      "Created" => at,
      "CurrentBookmark" => %{"LastModified" => at},
      "EntitlementId" => id,
      "LastModified" => at,
      "PriorityTimestamp" => at,
      "Statistics" => %{"LastModified" => at},
      "StatusInfo" => %{"LastModified" => at, "Status" => "ReadyToRead", "TimesStartedReading" => 0}
    }
  end

  defp reading_state(book_or_id, %ReadingProgress{} = progress) do
    {id, _created} = id_and_created(book_or_id)
    at = iso(progress.updated_at)
    locator = progress.locator || %{}

    status =
      cond do
        progress.progression >= 1.0 -> "Finished"
        progress.progression > 0.0 -> "Reading"
        true -> "ReadyToRead"
      end

    bookmark =
      %{
        "LastModified" => at,
        "ProgressPercent" => Float.round(progress.progression * 100, 2),
        "ContentSourceProgressPercent" => locator["kobo_chapter_progress"] && locator["kobo_chapter_progress"] * 100,
        "Location" =>
          locator["href"] && %{"Source" => locator["href"], "Type" => "KoboSpan", "Value" => locator["kobo_span"]}
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    %{
      "Created" => at,
      "CurrentBookmark" => bookmark,
      "EntitlementId" => id,
      "LastModified" => at,
      "PriorityTimestamp" => at,
      "Statistics" => %{"LastModified" => at},
      "StatusInfo" => %{"LastModified" => at, "Status" => status, "TimesStartedReading" => 1}
    }
  end

  defp id_and_created(%{id: id, inserted_at: created}), do: {id, created}
  defp id_and_created(id) when is_binary(id), do: {id, NaiveDateTime.utc_now()}

  ## Helpers

  defp urls(conn), do: %{books: "#{base_url(conn)}/kobo/#{conn.path_params["token"]}/v1/books"}

  # The address the device reached Stashix at, behind a reverse proxy too:
  # the device fetches books and covers from what this builds.
  defp base_url(conn) do
    scheme = List.first(get_req_header(conn, "x-forwarded-proto")) || to_string(conn.scheme)
    host = List.first(get_req_header(conn, "x-forwarded-host")) || List.first(get_req_header(conn, "host")) || conn.host
    "#{scheme}://#{host}"
  end

  defp iso(%DateTime{} = t), do: t |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso(%NaiveDateTime{} = t), do: t |> DateTime.from_naive!("Etc/UTC") |> iso()

  defp parse_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_time(_), do: nil

  defp string(value) when is_binary(value), do: String.slice(value, 0, 1024)
  defp string(_), do: nil

  defp random_token, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
end
