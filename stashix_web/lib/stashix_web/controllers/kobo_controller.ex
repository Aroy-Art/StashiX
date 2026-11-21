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

  Store calls Stashix has no part in (the shop, wishlists, analytics) get an
  empty answer: books bought from Kobo don't sync while the device points
  here.

  Reading state goes both ways: the device's spot (chapter, Kobo span and
  how far through) is saved as Stashix progress, and progress from the web
  readers and other apps goes back to the device on the next sync.
  """
  use StashixWeb, :controller

  import Ecto.Query

  alias Stashix.{Kobo, Library, Repo}
  alias Stashix.Library.{Access, ReadingProgress}

  @sync_limit 100
  @dummy_id "00000000-0000-0000-0000-000000000001"
  # The store's own resource URLs (from Komga's Kobo support), which the
  # device needs at start-up; the image ones are pointed here.
  @resources_path Path.expand("../../../priv/kobo/resources.json", __DIR__)
  @external_resource @resources_path
  @resources @resources_path |> File.read!() |> Jason.decode!()

  ## Device setup

  def initialization(conn, %{"token" => token}) do
    images = "#{base_url(conn)}/kobo/#{token}/v1/books/{ImageId}/thumbnail"

    resources =
      Map.merge(@resources, %{
        "image_host" => base_url(conn),
        "image_url_template" => images <> "/{Width}/{Height}/false/image.jpg",
        "image_url_quality_template" => images <> "/{Width}/{Height}/{Quality}/{IsGreyscale}/image.jpg"
      })

    conn
    |> put_resp_header("x-kobo-apitoken", "e30=")
    |> json(%{"Resources" => resources})
  end

  # The device asks for store tokens; Stashix signs it in by the URL instead.
  def auth_device(conn, params) do
    json(conn, %{
      "AccessToken" => random_token(),
      "RefreshToken" => random_token(),
      "TokenType" => "Bearer",
      "TrackingId" => Ecto.UUID.generate(),
      "UserKey" => params["UserKey"] || ""
    })
  end

  @doc "Store calls Stashix does not answer for."
  def other(conn, _params), do: json(conn, %{})

  ## Library sync

  @doc """
  The device's library, as changes since its last sync: new books, changed
  ones, removed ones and reading states, at most #{@sync_limit} at a time
  (`x-kobo-sync: continue` asks for the rest). The sync token holds when
  the last complete sync started (`since`) and, mid-way, when this one did.
  """
  def sync(conn, _params) do
    %{access: access, app_password: app_password, current_user: user} = conn.assigns
    token = read_sync_token(conn)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    round = parse_time(token["round"]) || now
    since = parse_time(token["since"])

    # A device without a token (new, or reset) starts over.
    if is_nil(since) and is_nil(token["round"]),
      do: Kobo.mark_removed(app_password.id, Map.keys(Kobo.synced(app_password.id)))

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

    next_token =
      if more?, do: %{"since" => token["since"], "round" => iso(round)}, else: %{"since" => iso(round)}

    conn
    |> put_resp_header("x-kobo-synctoken", next_token |> Jason.encode!() |> Base.encode64())
    |> then(&if(more?, do: put_resp_header(&1, "x-kobo-sync", "continue"), else: &1))
    |> json(results)
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
    book = kobo_book!(conn, id)
    json(conn, [book_metadata(book, urls(conn))])
  end

  def state(conn, %{"id" => id}) do
    book = kobo_book!(conn, id)
    json(conn, [reading_state(book, Library.get_progress(conn.assigns.current_user.id, book.id))])
  end

  @doc "The device's reading state for a book, saved as progress unless Stashix has a newer one."
  def update_state(conn, %{"id" => id} = params) do
    %{access: access, current_user: user} = conn.assigns
    book = kobo_book!(conn, id)

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

  def cover(conn, %{"id" => id, "width" => width}),
    do: StashixWeb.BookController.cover(conn, %{"id" => id, "w" => width})

  defp kobo_book!(conn, id) do
    # Books bought from Kobo have ids of their own: not ours.
    if Ecto.UUID.cast(id) == :error, do: raise(Ecto.NoResultsError, queryable: Stashix.Library.Book)
    book = conn.assigns.access |> Library.get_book!(id)

    if Access.can_download?(conn.assigns.access, book.library_id),
      do: book |> Repo.preload([:series, :publishers, :files, credits: :creator]),
      else: raise(Ecto.NoResultsError, queryable: Stashix.Library.Book)
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
