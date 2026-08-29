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
        left_join: b in Book,
          on: b.series_id == s.id and is_nil(b.deleted_at),
        where: s.library_id == ^library_id and is_nil(s.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)}

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], [asc_nulls_last: s.start_year, asc: s.name])
        "year_desc" -> order_by(query, [s], [desc_nulls_last: s.start_year, asc: s.name])
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query) |> Repo.preload(:publisher)
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
        where: b.page_count == 0 or rp.current_page < b.page_count - 1,
        order_by: [desc: rp.updated_at],
        limit: ^limit,
        select: {b, rp.current_page}
      )
      |> Repo.all()

    books = Enum.map(results, fn {book, _} -> book end)

    series_query =
      from s in Series,
        left_join: b in Book,
          on: b.series_id == s.id and is_nil(b.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)}

    loaded_map =
      Repo.preload(books, [:cover, [series: series_query]]) |> Map.new(&{&1.id, &1})

    Enum.map(results, fn {book, current_page} ->
      %{book: loaded_map[book.id], current_page: current_page}
    end)
  end

  def next_issue_books(user_id, limit \\ 20) do
    completed_by_series =
      from(rp in ReadingProgress,
        where: rp.user_id == ^user_id and rp.current_page > 0,
        join: b in Book,
          on: b.id == rp.book_id
            and is_nil(b.deleted_at)
            and not is_nil(b.series_id)
            and b.page_count > 0,
        where: rp.current_page >= b.page_count - 1,
        group_by: b.series_id,
        order_by: [desc: max(rp.updated_at)],
        select: {b.series_id, max(b.issue_number)},
        limit: ^limit
      )
      |> Repo.all()

    valid = Enum.reject(completed_by_series, fn {_, issue} -> is_nil(issue) end)

    if valid == [] do
      []
    else
      series_ids = Enum.map(valid, &elem(&1, 0))
      max_issues = Map.new(valid)

      from(b in Book,
        where: b.series_id in ^series_ids and is_nil(b.deleted_at),
        left_join: rp in ReadingProgress,
          on: rp.book_id == b.id and rp.user_id == ^user_id,
        where: is_nil(rp.id) or rp.current_page == 0,
        order_by: [asc: b.series_id, asc_nulls_last: b.issue_number],
        preload: [:cover, :series]
      )
      |> Repo.all()
      |> Enum.filter(fn b ->
        max = Map.get(max_issues, b.series_id)
        not is_nil(max) and not is_nil(b.issue_number) and b.issue_number > max
      end)
      |> Enum.uniq_by(& &1.series_id)
      |> Enum.take(limit)
    end
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

  def load_series_cache(library_id) do
    from(s in Series, where: s.library_id == ^library_id and is_nil(s.deleted_at), select: {s.name, s})
    |> Repo.all()
    |> Map.new()
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
    Repo.aggregate(
      from(b in Book, where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "standalone"),
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

  def total_size(library_id) do
    result = Repo.aggregate(
      from(b in Book, where: b.library_id == ^library_id and is_nil(b.deleted_at)),
      :sum,
      :file_size
    )
    case result do
      nil -> 0
      %Decimal{} = d -> Decimal.to_integer(d)
      n -> n
    end
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
      left_join: b in Book,
        on: b.series_id == s.id and is_nil(b.deleted_at),
      where: s.library_id == ^library_id and is_nil(s.deleted_at),
      group_by: s.id,
      order_by: [desc: s.inserted_at],
      limit: ^limit,
      select: %{s | issue_count: count(b.id)}
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

  def list_all_issues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    library_id = Keyword.get(opts, :library_id)

    query =
      from b in Book,
        left_join: s in assoc(b, :series),
        left_join: c in assoc(b, :cover),
        where: is_nil(b.deleted_at) and b.type == "issue",
        limit: ^limit,
        offset: ^offset,
        preload: [series: s, cover: c]

    query = if library_id, do: where(query, [b], b.library_id == ^library_id), else: query

    query =
      case sort do
        "title_desc" ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) DESC NULLS LAST, ? ASC NULLS LAST, ? DESC", s.name, b.title, b.issue_number, b.title)
          )
        "year_asc" ->
          order_by(query, [b, s],
            fragment("? ASC NULLS LAST, COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST", s.start_year, s.name, b.title, b.issue_number)
          )
        "year_desc" ->
          order_by(query, [b, s],
            fragment("? DESC NULLS LAST, COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST", s.start_year, s.name, b.title, b.issue_number)
          )
        "added_asc" ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST", s.inserted_at, b.inserted_at, b.issue_number)
          )
        "added_desc" ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) DESC NULLS LAST, ? ASC NULLS LAST", s.inserted_at, b.inserted_at, b.issue_number)
          )
        "issue_asc" ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST", s.name, b.title, b.issue_number)
          )
        "issue_desc" ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) ASC NULLS LAST, ? DESC NULLS LAST", s.name, b.title, b.issue_number)
          )
        _ ->
          order_by(query, [b, s],
            fragment("COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST, ? ASC", s.name, b.title, b.issue_number, b.title)
          )
      end

    Repo.all(query)
  end

  def list_series_for_issues(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    library_id = Keyword.get(opts, :library_id)

    query =
      from s in Series,
        where:
          is_nil(s.deleted_at) and
            fragment(
              "EXISTS (SELECT 1 FROM books WHERE books.series_id = ? AND books.deleted_at IS NULL AND books.type = 'issue')",
              s.id
            ),
        limit: ^limit,
        offset: ^offset

    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], [asc_nulls_last: s.start_year, asc: s.name])
        "year_desc" -> order_by(query, [s], [desc_nulls_last: s.start_year, asc: s.name])
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    issues_query =
      from b in Book,
        where: is_nil(b.deleted_at) and b.type == "issue",
        order_by: [asc_nulls_last: b.issue_number, asc: b.title]

    Repo.all(query) |> Repo.preload(books: {issues_query, [:cover]})
  end

  def count_series_for_issues(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query =
      from s in Series,
        where:
          is_nil(s.deleted_at) and
            fragment(
              "EXISTS (SELECT 1 FROM books WHERE books.series_id = ? AND books.deleted_at IS NULL AND books.type = 'issue')",
              s.id
            )

    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query
    Repo.aggregate(query, :count, :id)
  end

  def list_ungrouped_issues(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query =
      from b in Book,
        where: is_nil(b.deleted_at) and b.type == "issue" and is_nil(b.series_id),
        order_by: [asc: b.title],
        preload: [:cover]

    query = if library_id, do: where(query, [b], b.library_id == ^library_id), else: query
    Repo.all(query)
  end

  def list_all_books(opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    type = Keyword.get(opts, :type)
    library_id = Keyword.get(opts, :library_id)

    query =
      from b in Book,
        where: is_nil(b.deleted_at),
        preload: [:cover, :series],
        limit: ^limit,
        offset: ^offset

    query = if type, do: where(query, [b], b.type == ^type), else: query
    query = if library_id, do: where(query, [b], b.library_id == ^library_id), else: query

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

  def count_all_books(opts \\ []) do
    type = Keyword.get(opts, :type)
    library_id = Keyword.get(opts, :library_id)

    query = from b in Book, where: is_nil(b.deleted_at)
    query = if type, do: where(query, [b], b.type == ^type), else: query
    query = if library_id, do: where(query, [b], b.library_id == ^library_id), else: query

    Repo.aggregate(query, :count, :id)
  end

  def list_all_series(opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    library_id = Keyword.get(opts, :library_id)

    query =
      from s in Series,
        left_join: b in Book,
          on: b.series_id == s.id and is_nil(b.deleted_at),
        where: is_nil(s.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)},
        limit: ^limit,
        offset: ^offset

    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], [asc_nulls_last: s.start_year, asc: s.name])
        "year_desc" -> order_by(query, [s], [desc_nulls_last: s.start_year, asc: s.name])
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query) |> Repo.preload(:publisher)
  end

  def count_all_series(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query = from s in Series, where: is_nil(s.deleted_at)
    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query

    Repo.aggregate(query, :count, :id)
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
