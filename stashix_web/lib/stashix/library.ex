defmodule Stashix.Library do
  import Ecto.Query
  alias Stashix.Repo
  alias Stashix.Library.{Library, Book, Series, BookCover, LibraryPermission, ReadingProgress}

  def list_libraries(user) do
    if user.role == :admin do
      Repo.all(Library)
    else
      from(l in Library,
        join: p in LibraryPermission,
        on: p.library_id == l.id and p.user_id == ^user.id and p.can_read == true
      )
      |> Repo.all()
    end
  end

  def get_library!(id), do: Repo.get!(Library, id)

  def create_library(attrs) do
    %Library{}
    |> Library.changeset(attrs)
    |> Repo.insert()
  end

  def update_library(library, attrs) do
    library
    |> Library.changeset(attrs)
    |> Repo.update()
  end

  def list_books(library_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    type = Keyword.get(opts, :type)
    series_id = Keyword.get(opts, :series_id)

    query =
      from b in Book,
        where: b.library_id == ^library_id and is_nil(b.deleted_at),
        preload: [:cover, :series],
        limit: ^limit,
        offset: ^offset

    query =
      if type do
        where(query, [b], b.type == ^type)
      else
        query
      end

    query =
      if series_id do
        where(query, [b], b.series_id == ^series_id)
      else
        query
      end

    query =
      case sort do
        "title_desc" -> order_by(query, [b], desc: b.title)
        "year_asc" -> order_by(query, [b], [asc_nulls_last: b.year, asc: b.title])
        "year_desc" -> order_by(query, [b], [desc_nulls_last: b.year, asc: b.title])
        "added_asc" -> order_by(query, [b], asc: b.inserted_at)
        "added_desc" -> order_by(query, [b], desc: b.inserted_at)
        "issue_asc" -> order_by(query, [b], [asc_nulls_last: b.issue_number, asc: b.title])
        "issue_desc" -> order_by(query, [b], [desc_nulls_last: b.issue_number, asc: b.title])
        _ -> order_by(query, [b], asc: b.title)
      end

    Repo.all(query)
  end

  def get_book!(id), do: Repo.get!(Book, id)

  def get_book_with_series(id) do
    Repo.get!(Book, id) |> Repo.preload([:series, :cover, :publisher])
  end

  def list_series(library_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, "title_asc")

    query =
      from s in Series,
        where: s.library_id == ^library_id and is_nil(s.deleted_at),
        select: %{
          s
          | issue_count:
              fragment(
                "(SELECT COUNT(*) FROM books WHERE series_id = ? AND deleted_at IS NULL)",
                s.id
              )
        },
        preload: [:publisher]

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], [asc_nulls_last: s.start_year, asc: s.name])
        "year_desc" -> order_by(query, [s], [desc_nulls_last: s.start_year, asc: s.name])
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query)
  end

  def get_series!(id), do: Repo.get!(Series, id)

  def get_series_with_books(id) do
    books_query = from(b in Book, where: is_nil(b.deleted_at), order_by: [asc: b.issue_number])
    Repo.get!(Series, id) |> Repo.preload([:publisher, books: {books_query, [:cover]}])
  end

  def update_progress(user_id, book_id, page) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert(
      %ReadingProgress{
        user_id: user_id,
        book_id: book_id,
        current_page: page,
        updated_at: now
      },
      on_conflict: [set: [current_page: page, updated_at: now]],
      conflict_target: [:user_id, :book_id]
    )
  end

  def get_progress(user_id, book_id) do
    Repo.get_by(ReadingProgress, user_id: user_id, book_id: book_id)
  end

  def progress_map(_user_id, []), do: %{}

  def progress_map(user_id, book_ids) do
    from(rp in ReadingProgress,
      where: rp.user_id == ^user_id and rp.book_id in ^book_ids and rp.current_page > 0,
      select: {rp.book_id, rp.current_page}
    )
    |> Repo.all()
    |> Map.new()
  end

  def in_progress_books(user_id, limit \\ 20) do
    results =
      from(rp in ReadingProgress,
        where: rp.user_id == ^user_id and rp.current_page > 0,
        join: b in Book,
        on: b.id == rp.book_id and is_nil(b.deleted_at),
        order_by: [desc: rp.updated_at],
        limit: ^limit,
        select: {b, rp.current_page}
      )
      |> Repo.all()

    books = Enum.map(results, fn {book, _} -> book end)
    series_query =
      from s in Series,
        select: %{
          s
          | issue_count:
              fragment(
                "(SELECT COUNT(*) FROM books WHERE series_id = ? AND deleted_at IS NULL)",
                s.id
              )
        }

    loaded_map =
      Repo.preload(books, [:cover, [series: series_query]]) |> Map.new(&{&1.id, &1})

    Enum.map(results, fn {book, current_page} ->
      %{book: loaded_map[book.id], current_page: current_page}
    end)
  end

  def search_books(query_string, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(b in Book,
      where:
        fragment("search_vec @@ plainto_tsquery('english', ?)", ^query_string) and
          is_nil(b.deleted_at),
      order_by: fragment("ts_rank(search_vec, plainto_tsquery('english', ?)) DESC", ^query_string),
      preload: [:cover, :series],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  def get_series_cover(series_id) do
    series = Repo.get!(Series, series_id)

    folder_cover =
      series.path &&
        Enum.find_value(~w(cover.jpg cover.jpeg cover.png cover.webp), fn name ->
          path = Path.join(series.path, name)
          if File.exists?(path), do: path
        end)

    folder_cover ||
      from(bc in BookCover,
        join: b in Book,
        on: b.id == bc.book_id,
        where: b.series_id == ^series_id and is_nil(b.deleted_at),
        order_by: [asc_nulls_last: b.issue_number, asc: b.inserted_at],
        limit: 1,
        select: bc.path
      )
      |> Repo.one()
  end

  def update_series_counts(library_id) do
    {:ok, uuid_bin} = Ecto.UUID.dump(library_id)

    Repo.query!(
      """
      UPDATE series
      SET issue_count = (
        SELECT COUNT(*) FROM books
        WHERE books.series_id = series.id AND books.deleted_at IS NULL
      )
      WHERE series.library_id = $1
      """,
      [uuid_bin]
    )
  end

  def create_or_find_series(attrs) do
    case Repo.get_by(Series, library_id: attrs.library_id, name: attrs.name) do
      nil ->
        %Series{}
        |> Series.changeset(attrs)
        |> Repo.insert()

      series ->
        series
        |> Series.changeset(Map.take(attrs, [:start_year, :end_year, :ongoing, :path]))
        |> Repo.update()
    end
  end

  def create_book(attrs) do
    %Book{}
    |> Book.changeset(attrs)
    |> Repo.insert()
  end

  def update_book(book, attrs) do
    book
    |> Book.changeset(attrs)
    |> Repo.update()
  end

  def get_book_by_path(path) do
    Repo.get_by(Book, path: path)
  end

  def get_book_by_hash(hash) do
    Repo.get_by(Book, file_hash: hash)
  end

  def create_or_update_cover(book_id, path) do
    case Repo.get_by(BookCover, book_id: book_id) do
      nil ->
        %BookCover{}
        |> BookCover.changeset(%{book_id: book_id, path: path})
        |> Repo.insert()

      cover ->
        cover
        |> BookCover.changeset(%{path: path})
        |> Repo.update()
    end
  end

  def set_library_permission(attrs) do
    case Repo.get_by(LibraryPermission,
           user_id: attrs[:user_id],
           library_id: attrs[:library_id]
         ) do
      nil ->
        %LibraryPermission{}
        |> LibraryPermission.changeset(attrs)
        |> Repo.insert()

      permission ->
        permission
        |> LibraryPermission.changeset(attrs)
        |> Repo.update()
    end
  end

  def count_books(library_id) do
    Repo.aggregate(from(b in Book, where: b.library_id == ^library_id and is_nil(b.deleted_at)),
      :count,
      :id
    )
  end

  def count_series(library_id) do
    Repo.aggregate(
      from(s in Series, where: s.library_id == ^library_id and is_nil(s.deleted_at)),
      :count,
      :id
    )
  end

  def count_issues(library_id) do
    Repo.aggregate(
      from(b in Book, where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "issue"),
      :count,
      :id
    )
  end

  def recent_books(library_id, limit \\ 10, type \\ nil) do
    query =
      from b in Book,
        where: b.library_id == ^library_id and is_nil(b.deleted_at),
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        preload: [:cover]

    query =
      if type, do: where(query, [b], b.type == ^type), else: query

    Repo.all(query)
  end

  def recent_series(library_id, limit \\ 10) do
    from(s in Series,
      where: s.library_id == ^library_id and is_nil(s.deleted_at),
      order_by: [desc: s.inserted_at],
      limit: ^limit,
      select: %{
        s
        | issue_count:
            fragment(
              "(SELECT COUNT(*) FROM books WHERE series_id = ? AND deleted_at IS NULL)",
              s.id
            )
      }
    )
    |> Repo.all()
  end

  def recent_issues(library_id, limit \\ 10) do
    from(b in Book,
      where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "issue",
      order_by: [desc: b.inserted_at],
      limit: ^limit,
      preload: [:cover]
    )
    |> Repo.all()
  end

  def mark_orphaned_books(library_id, scanned_paths) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(b in Book,
      where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.path not in ^scanned_paths
    )
    |> Repo.update_all(set: [deleted_at: now])
  end

  def mark_empty_series_deleted(library_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    active_series_ids =
      from(b in Book,
        where: not is_nil(b.series_id) and is_nil(b.deleted_at),
        select: b.series_id,
        distinct: true
      )

    from(s in Series,
      where:
        s.library_id == ^library_id and is_nil(s.deleted_at) and
          s.id not in subquery(active_series_ids)
    )
    |> Repo.update_all(set: [deleted_at: now])
  end

  def list_all_deleted_books do
    from(b in Book,
      where: not is_nil(b.deleted_at),
      preload: [:series, :cover, :library],
      order_by: [desc: b.deleted_at]
    )
    |> Repo.all()
  end

  def list_all_deleted_series do
    from(s in Series,
      where: not is_nil(s.deleted_at),
      preload: [:library],
      order_by: [desc: s.deleted_at]
    )
    |> Repo.all()
  end

  def restore_book(book) do
    book |> Book.changeset(%{deleted_at: nil}) |> Repo.update()
  end

  def restore_series(series) do
    Repo.transaction(fn ->
      from(b in Book, where: b.series_id == ^series.id and not is_nil(b.deleted_at))
      |> Repo.update_all(set: [deleted_at: nil])

      series |> Series.changeset(%{deleted_at: nil}) |> Repo.update!()
    end)
  end

  def purge_book(book) do
    Repo.transaction(fn ->
      Repo.delete_all(from bc in BookCover, where: bc.book_id == ^book.id)
      Repo.delete!(book)
    end)
  end

  def purge_series(series) do
    Repo.transaction(fn ->
      book_ids =
        from(b in Book, where: b.series_id == ^series.id, select: b.id) |> Repo.all()

      Repo.delete_all(from bc in BookCover, where: bc.book_id in ^book_ids)
      Repo.delete_all(from b in Book, where: b.id in ^book_ids)
      Repo.delete!(series)
    end)
  end

  def batch_restore_books(ids) do
    from(b in Book, where: b.id in ^ids)
    |> Repo.update_all(set: [deleted_at: nil])
  end

  def batch_purge_books(ids) do
    Repo.transaction(fn ->
      Repo.delete_all(from bc in BookCover, where: bc.book_id in ^ids)
      Repo.delete_all(from b in Book, where: b.id in ^ids)
    end)
  end

  def batch_restore_series(ids) do
    Repo.transaction(fn ->
      from(b in Book, where: b.series_id in ^ids and not is_nil(b.deleted_at))
      |> Repo.update_all(set: [deleted_at: nil])

      from(s in Series, where: s.id in ^ids)
      |> Repo.update_all(set: [deleted_at: nil])
    end)
  end

  def batch_purge_series(ids) do
    Repo.transaction(fn ->
      book_ids = from(b in Book, where: b.series_id in ^ids, select: b.id) |> Repo.all()
      Repo.delete_all(from bc in BookCover, where: bc.book_id in ^book_ids)
      Repo.delete_all(from b in Book, where: b.id in ^book_ids)
      Repo.delete_all(from s in Series, where: s.id in ^ids)
    end)
  end
end
