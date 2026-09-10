defmodule Stashix.Library do
  import Ecto.Query
  alias Stashix.Repo

  alias Stashix.Library.{
    Library,
    Book,
    Series,
    BookCover,
    LibraryPermission,
    ReadingProgress,
    Publisher
  }

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
        "year_asc" -> order_by(query, [b], asc_nulls_last: b.year, asc: b.title)
        "year_desc" -> order_by(query, [b], desc_nulls_last: b.year, asc: b.title)
        "added_asc" -> order_by(query, [b], asc: b.inserted_at)
        "added_desc" -> order_by(query, [b], desc: b.inserted_at)
        "issue_asc" -> order_by(query, [b], asc_nulls_last: b.issue_number, asc: b.title)
        "issue_desc" -> order_by(query, [b], desc_nulls_last: b.issue_number, asc: b.title)
        _ -> order_by(query, [b], asc: b.title)
      end

    Repo.all(query)
  end

  def get_book!(id), do: Repo.get!(Book, id)

  def get_book_with_series(id) do
    Repo.get!(Book, id) |> Repo.preload([:series, :cover, :publishers])
  end

  def get_adjacent_books(%{series_id: nil}), do: {nil, nil}

  def get_adjacent_books(%{series_id: _series_id, issue_number: nil}), do: {nil, nil}

  def get_adjacent_books(%{id: id, series_id: series_id, issue_number: _issue_number}) do
    siblings =
      from(b in Book,
        left_join: c in BookCover,
        on: c.book_id == b.id,
        where: b.series_id == ^series_id and is_nil(b.deleted_at) and not is_nil(b.issue_number),
        order_by: [asc: b.issue_number],
        select: %{
          id: b.id,
          issue_number: b.issue_number,
          title: b.title,
          year: b.year,
          page_count: b.page_count,
          blurhash: c.blurhash
        }
      )
      |> Repo.all()

    idx = Enum.find_index(siblings, &(&1.id == id))

    prev = idx && idx > 0 && Enum.at(siblings, idx - 1)
    next = idx && Enum.at(siblings, idx + 1)

    {prev || nil, next || nil}
  end

  def list_series(library_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, "title_asc")
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from s in Series,
        left_join: b in Book,
        on: b.series_id == s.id and is_nil(b.deleted_at),
        where: s.library_id == ^library_id and is_nil(s.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)},
        offset: ^offset

    query = if limit, do: limit(query, ^limit), else: query

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], asc_nulls_last: s.start_year, asc: s.name)
        "year_desc" -> order_by(query, [s], desc_nulls_last: s.start_year, asc: s.name)
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query) |> Repo.preload(:publishers) |> attach_series_blurhashes()
  end

  def get_series!(id), do: Repo.get!(Series, id)

  def get_series_with_books(id) do
    books_query = from(b in Book, where: is_nil(b.deleted_at), order_by: [asc: b.issue_number])
    Repo.get!(Series, id) |> Repo.preload([:publishers, books: {books_query, [:cover]}])
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
        on:
          b.id == rp.book_id and
            is_nil(b.deleted_at) and
            not is_nil(b.series_id) and
            b.page_count > 0,
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

  def search_all(query_string, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    books =
      from(b in Book,
        where:
          fragment("search_vec @@ plainto_tsquery('english', ?)", ^query_string) and
            is_nil(b.deleted_at),
        order_by: fragment("ts_rank(search_vec, plainto_tsquery('english', ?)) DESC", ^query_string),
        preload: [:cover, :series],
        limit: ^limit
      )
      |> Repo.all()

    pattern = "%#{String.replace(query_string, "%", "\\%")}%"

    series =
      from(s in Series,
        left_join: b in Book,
        on: b.series_id == s.id and is_nil(b.deleted_at),
        where: ilike(s.name, ^pattern) and is_nil(s.deleted_at),
        group_by: s.id,
        order_by: [asc: s.name],
        select: %{s | issue_count: count(b.id)},
        limit: ^limit
      )
      |> Repo.all()
      |> attach_series_blurhashes()

    %{
      series: series,
      issues: Enum.filter(books, &(&1.type == "issue")),
      books: Enum.filter(books, &(&1.type == "standalone"))
    }
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
    from(s in Series,
      where: s.library_id == ^library_id and is_nil(s.deleted_at),
      select: {s.path, s}
    )
    |> Repo.all()
    |> Map.new()
  end

  def load_hash_series_map(library_id, hashes) do
    from(b in Book,
      join: s in Series,
      on: s.id == b.series_id,
      where: b.library_id == ^library_id and b.file_hash in ^hashes and is_nil(b.deleted_at),
      select: {b.file_hash, s}
    )
    |> Repo.all()
    |> Map.new()
  end

  def find_series_by_book_hashes(library_id, hashes) do
    series_id =
      from(b in Book,
        where: b.library_id == ^library_id and b.file_hash in ^hashes and is_nil(b.deleted_at),
        group_by: b.series_id,
        order_by: [desc: count(b.id)],
        limit: 1,
        select: b.series_id
      )
      |> Repo.one()

    case series_id do
      nil -> nil
      id -> Repo.get(Series, id)
    end
  end

  def create_or_find_series(attrs) do
    case Repo.get_by(Series, library_id: attrs.library_id, path: attrs.path) do
      nil ->
        %Series{}
        |> Series.changeset(attrs)
        |> Repo.insert()

      series ->
        series
        |> Series.changeset(Map.take(attrs, [:name, :start_year, :end_year, :ongoing, :path]))
        |> Repo.update()
    end
  end

  def update_series(series, attrs) do
    series
    |> Series.changeset(attrs)
    |> Repo.update()
  end

  def update_series_folder_meta(series, attrs) do
    series
    |> Series.changeset(Map.take(attrs, [:name, :path, :start_year, :end_year, :ongoing]))
    |> Repo.update()
  end

  def create_book(attrs) do
    %Book{}
    |> Book.changeset(attrs)
    |> Repo.insert()
  end

  def get_publisher!(id), do: Repo.get!(Publisher, id)

  def get_publisher_with_aliases!(id) do
    Repo.get!(Publisher, id) |> Repo.preload([:aliases, :canonical])
  end

  def set_publisher_alias(alias_id, master_id) when alias_id == master_id,
    do: {:error, :same_publisher}

  def set_publisher_alias(alias_id, master_id) do
    Repo.get!(Publisher, alias_id)
    |> Publisher.changeset(%{canonical_publisher_id: master_id})
    |> Repo.update()
  end

  def remove_publisher_alias(publisher_id) do
    Repo.get!(Publisher, publisher_id)
    |> Publisher.changeset(%{canonical_publisher_id: nil})
    |> Repo.update()
  end

  # Returns all binary UUIDs for a publisher: the master + any aliases
  defp publisher_id_bins(publisher_id) do
    alias_bins =
      from(p in Publisher,
        where: p.canonical_publisher_id == ^publisher_id,
        select: p.id
      )
      |> Repo.all()
      |> Enum.map(&Ecto.UUID.dump!/1)

    [Ecto.UUID.dump!(publisher_id) | alias_bins]
  end

  def list_publisher_series(publisher_id, opts \\ []) do
    sort = Keyword.get(opts, :sort, "title_asc")
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    pub_bins = publisher_id_bins(publisher_id)

    query =
      from s in Series,
        join: sp in "series_publishers",
        on: sp.series_id == s.id,
        where: sp.publisher_id in ^pub_bins and is_nil(s.deleted_at),
        distinct: true,
        limit: ^limit,
        offset: ^offset

    query =
      case sort do
        "title_desc" -> order_by(query, [s], desc: s.name)
        "year_asc" -> order_by(query, [s], asc_nulls_last: s.start_year, asc: s.name)
        "year_desc" -> order_by(query, [s], desc_nulls_last: s.start_year, asc: s.name)
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query) |> attach_series_blurhashes()
  end

  def count_publisher_series(publisher_id) do
    pub_bins = publisher_id_bins(publisher_id)

    from(s in Series,
      join: sp in "series_publishers",
      on: sp.series_id == s.id,
      where: sp.publisher_id in ^pub_bins and is_nil(s.deleted_at),
      distinct: true
    )
    |> Repo.aggregate(:count, :id)
  end

  def list_publisher_books(publisher_id, opts \\ []) do
    type = Keyword.get(opts, :type, "standalone")
    sort = Keyword.get(opts, :sort, "title_asc")
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    pub_bins = publisher_id_bins(publisher_id)

    query =
      from b in Book,
        join: bp in "book_publishers",
        on: bp.book_id == b.id,
        where: bp.publisher_id in ^pub_bins and is_nil(b.deleted_at) and b.type == ^type,
        distinct: true,
        preload: [:cover, :series],
        limit: ^limit,
        offset: ^offset

    query =
      case sort do
        "title_desc" -> order_by(query, [b], desc: b.title)
        "year_asc" -> order_by(query, [b], asc_nulls_last: b.year, asc: b.title)
        "year_desc" -> order_by(query, [b], desc_nulls_last: b.year, asc: b.title)
        "added_asc" -> order_by(query, [b], asc: b.inserted_at)
        "added_desc" -> order_by(query, [b], desc: b.inserted_at)
        "issue_asc" -> order_by(query, [b], asc_nulls_last: b.issue_number, asc: b.title)
        "issue_desc" -> order_by(query, [b], desc_nulls_last: b.issue_number, asc: b.title)
        _ -> order_by(query, [b], asc: b.title)
      end

    Repo.all(query)
  end

  def count_publisher_books(publisher_id, type) do
    pub_bins = publisher_id_bins(publisher_id)

    from(b in Book,
      join: bp in "book_publishers",
      on: bp.book_id == b.id,
      where: bp.publisher_id in ^pub_bins and is_nil(b.deleted_at) and b.type == ^type,
      distinct: true
    )
    |> Repo.aggregate(:count, :id)
  end

  def list_publishers do
    from(p in Publisher,
      where: is_nil(p.canonical_publisher_id) and not p.hidden,
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  def list_all_publishers do
    from(p in Publisher, order_by: [asc: p.name])
    |> Repo.all()
  end

  def list_all_publishers_admin(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    page = Keyword.get(opts, :page, 1)
    search = Keyword.get(opts, :search, "")

    base =
      if search != "" do
        term = "%#{search}%"
        from(p in Publisher, where: ilike(p.name, ^term), order_by: [asc: p.name])
      else
        from(p in Publisher, order_by: [asc: p.name])
      end

    total = Repo.aggregate(base, :count, :id)

    items =
      Repo.all(from p in base, limit: ^limit, offset: ^((page - 1) * limit))
      |> Repo.preload(:canonical)

    {items, total}
  end

  def toggle_publisher_hidden(publisher_id) do
    pub = Repo.get!(Publisher, publisher_id)

    pub
    |> Publisher.changeset(%{hidden: !pub.hidden})
    |> Repo.update()
  end

  def list_publishers_with_aliases do
    from(p in Publisher,
      where: not is_nil(p.canonical_publisher_id),
      preload: :canonical,
      order_by: [asc: p.name]
    )
    |> Repo.all()
  end

  def merge_publishers(source_id, target_id) when source_id == target_id,
    do: {:error, :same_publisher}

  def merge_publishers(source_id, target_id) do
    source_bin = Ecto.UUID.dump!(source_id)
    target_bin = Ecto.UUID.dump!(target_id)

    Repo.transaction(fn ->
      book_ids =
        from(bp in "book_publishers", where: bp.publisher_id == ^source_bin, select: bp.book_id)
        |> Repo.all()

      if book_ids != [] do
        Repo.insert_all(
          "book_publishers",
          Enum.map(book_ids, &%{book_id: &1, publisher_id: target_bin}),
          on_conflict: :nothing
        )
      end

      series_ids =
        from(sp in "series_publishers",
          where: sp.publisher_id == ^source_bin,
          select: sp.series_id
        )
        |> Repo.all()

      if series_ids != [] do
        Repo.insert_all(
          "series_publishers",
          Enum.map(series_ids, &%{series_id: &1, publisher_id: target_bin}),
          on_conflict: :nothing
        )
      end

      from(bp in "book_publishers", where: bp.publisher_id == ^source_bin) |> Repo.delete_all()
      from(sp in "series_publishers", where: sp.publisher_id == ^source_bin) |> Repo.delete_all()
      Repo.get!(Publisher, source_id) |> Repo.delete!()
    end)
  end

  def count_publishers do
    from(p in Publisher, where: is_nil(p.canonical_publisher_id) and not p.hidden)
    |> Repo.aggregate(:count, :id)
  end

  def list_publishers_paginated(opts \\ []) do
    limit = Keyword.get(opts, :limit, 24)
    offset = Keyword.get(opts, :offset, 0)

    from(p in Publisher,
      where: is_nil(p.canonical_publisher_id) and not p.hidden,
      order_by: [asc: p.name],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  def publisher_stats(publisher_ids) when publisher_ids == [], do: %{}

  def publisher_stats(publisher_ids) do
    # Build map of all IDs (master + aliases) -> master ID
    alias_rows =
      from(p in Publisher,
        where: p.canonical_publisher_id in ^publisher_ids,
        select: {p.canonical_publisher_id, p.id}
      )
      |> Repo.all()

    id_to_master =
      publisher_ids
      |> Enum.into(%{}, &{&1, &1})
      |> Map.merge(Map.new(alias_rows, fn {master, alias_id} -> {alias_id, master} end))

    all_bins = Map.keys(id_to_master) |> Enum.map(&Ecto.UUID.dump!/1)

    sum_by_master = fn rows ->
      Enum.reduce(rows, %{}, fn {raw_id, count}, acc ->
        master_id = Map.get(id_to_master, Ecto.UUID.cast!(raw_id))
        Map.update(acc, master_id, count, &(&1 + count))
      end)
    end

    series_counts =
      from(sp in "series_publishers",
        join: s in Series,
        on: s.id == sp.series_id,
        where: sp.publisher_id in ^all_bins and is_nil(s.deleted_at),
        group_by: sp.publisher_id,
        select: {sp.publisher_id, count(s.id)}
      )
      |> Repo.all()
      |> sum_by_master.()

    books_counts =
      from(bp in "book_publishers",
        join: b in Book,
        on: b.id == bp.book_id,
        where: bp.publisher_id in ^all_bins and is_nil(b.deleted_at) and b.type == "standalone",
        group_by: bp.publisher_id,
        select: {bp.publisher_id, count(b.id)}
      )
      |> Repo.all()
      |> sum_by_master.()

    issues_counts =
      from(bp in "book_publishers",
        join: b in Book,
        on: b.id == bp.book_id,
        where: bp.publisher_id in ^all_bins and is_nil(b.deleted_at) and b.type == "issue",
        group_by: bp.publisher_id,
        select: {bp.publisher_id, count(b.id)}
      )
      |> Repo.all()
      |> sum_by_master.()

    Enum.into(publisher_ids, %{}, fn id ->
      {id,
       %{
         series_count: Map.get(series_counts, id, 0),
         books_count: Map.get(books_counts, id, 0),
         issues_count: Map.get(issues_counts, id, 0)
       }}
    end)
  end

  def publisher_sample_covers(publisher_ids) when publisher_ids == [], do: %{}

  def publisher_sample_covers(publisher_ids) do
    alias_rows =
      from(p in Publisher,
        where: p.canonical_publisher_id in ^publisher_ids,
        select: {p.canonical_publisher_id, p.id}
      )
      |> Repo.all()

    id_to_master =
      publisher_ids
      |> Enum.into(%{}, &{&1, &1})
      |> Map.merge(Map.new(alias_rows, fn {master, alias_id} -> {alias_id, master} end))

    all_bins = Map.keys(id_to_master) |> Enum.map(&Ecto.UUID.dump!/1)

    from(bp in "book_publishers",
      join: b in Book,
      on: b.id == bp.book_id,
      join: _c in BookCover,
      on: _c.book_id == b.id,
      where: bp.publisher_id in ^all_bins and is_nil(b.deleted_at),
      select: {bp.publisher_id, bp.book_id}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {pub_id, _} -> Map.get(id_to_master, Ecto.UUID.cast!(pub_id)) end,
      fn {_, book_id} -> Ecto.UUID.cast!(book_id) end
    )
    |> Enum.into(%{}, fn {master_id, book_ids} ->
      {master_id, book_ids |> Enum.uniq() |> Enum.shuffle() |> Enum.take(5)}
    end)
  end

  def get_or_create_publisher(name) do
    case Repo.get_by(Publisher, name: name) do
      nil ->
        %Publisher{}
        |> Publisher.changeset(%{name: name})
        |> Repo.insert()

      publisher ->
        {:ok, publisher}
    end
  end

  def link_publisher_to_book(book_id, publisher_id) do
    Repo.insert_all(
      "book_publishers",
      [%{book_id: Ecto.UUID.dump!(book_id), publisher_id: Ecto.UUID.dump!(publisher_id)}],
      on_conflict: :nothing
    )

    :ok
  end

  def link_publisher_to_series(series_id, publisher_id) do
    Repo.insert_all(
      "series_publishers",
      [%{series_id: Ecto.UUID.dump!(series_id), publisher_id: Ecto.UUID.dump!(publisher_id)}],
      on_conflict: :nothing
    )

    :ok
  end

  def update_book(book, attrs) do
    book
    |> Book.changeset(attrs)
    |> Repo.update()
  end

  def load_books_cache(library_id) do
    from(b in Book,
      where: b.library_id == ^library_id,
      select: {b.path, %{last_modified: b.last_modified, deleted_at: b.deleted_at, file_hash: b.file_hash}}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_book_by_path(path) do
    Repo.get_by(Book, path: path)
  end

  def get_book_by_hash(hash) do
    Repo.get_by(Book, file_hash: hash)
  end

  def create_or_update_cover(book_id, path, blurhash \\ nil) do
    attrs = %{book_id: book_id, path: path, blurhash: blurhash}

    case Repo.get_by(BookCover, book_id: book_id) do
      nil ->
        %BookCover{}
        |> BookCover.changeset(attrs)
        |> Repo.insert()

      cover ->
        cover
        |> BookCover.changeset(Map.delete(attrs, :book_id))
        |> Repo.update()
    end
  end

  def list_covers_without_blurhash do
    from(bc in BookCover,
      join: b in Book,
      on: b.id == bc.book_id,
      where: is_nil(bc.blurhash) and not is_nil(bc.path),
      select: {b.id, bc.path}
    )
    |> Repo.all()
  end

  def series_cover_blurhash_map([]), do: %{}

  def series_cover_blurhash_map(series_ids) do
    from(bc in BookCover,
      join: b in Book,
      on: b.id == bc.book_id and is_nil(b.deleted_at),
      where: b.series_id in ^series_ids,
      distinct: [asc: b.series_id],
      order_by: [asc: b.series_id, asc_nulls_last: b.issue_number, asc: b.inserted_at],
      select: {b.series_id, bc.blurhash}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp attach_series_blurhashes([]), do: []

  defp attach_series_blurhashes(series) do
    ids = Enum.map(series, & &1.id)
    bh_map = series_cover_blurhash_map(ids)
    Enum.map(series, fn s -> %{s | cover_blurhash: Map.get(bh_map, s.id)} end)
  end

  def list_user_permissions(user_id) do
    from(p in LibraryPermission, where: p.user_id == ^user_id)
    |> Repo.all()
    |> Map.new(&{&1.library_id, &1})
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
      from(b in Book,
        where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "standalone"
      ),
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
      from(b in Book,
        where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "issue"
      ),
      :count,
      :id
    )
  end

  def total_size(library_id) do
    result =
      Repo.aggregate(
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
    |> attach_series_blurhashes()
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

  def mark_orphaned_series_books(series_id, scanned_paths) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(b in Book,
      where: b.series_id == ^series_id and is_nil(b.deleted_at) and b.path not in ^scanned_paths
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
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) DESC NULLS LAST, ? ASC NULLS LAST, ? DESC",
              s.name,
              b.title,
              b.issue_number,
              b.title
            )
          )

        "year_asc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "? ASC NULLS LAST, COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST",
              s.start_year,
              s.name,
              b.title,
              b.issue_number
            )
          )

        "year_desc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "? DESC NULLS LAST, COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST",
              s.start_year,
              s.name,
              b.title,
              b.issue_number
            )
          )

        "added_asc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST",
              s.inserted_at,
              b.inserted_at,
              b.issue_number
            )
          )

        "added_desc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) DESC NULLS LAST, ? ASC NULLS LAST",
              s.inserted_at,
              b.inserted_at,
              b.issue_number
            )
          )

        "issue_asc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST",
              s.name,
              b.title,
              b.issue_number
            )
          )

        "issue_desc" ->
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) ASC NULLS LAST, ? DESC NULLS LAST",
              s.name,
              b.title,
              b.issue_number
            )
          )

        _ ->
          order_by(
            query,
            [b, s],
            fragment(
              "COALESCE(?, ?) ASC NULLS LAST, ? ASC NULLS LAST, ? ASC",
              s.name,
              b.title,
              b.issue_number,
              b.title
            )
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
        "year_asc" -> order_by(query, [s], asc_nulls_last: s.start_year, asc: s.name)
        "year_desc" -> order_by(query, [s], desc_nulls_last: s.start_year, asc: s.name)
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
        "year_asc" -> order_by(query, [b], asc_nulls_last: b.year, asc: b.title)
        "year_desc" -> order_by(query, [b], desc_nulls_last: b.year, asc: b.title)
        "added_asc" -> order_by(query, [b], asc: b.inserted_at)
        "added_desc" -> order_by(query, [b], desc: b.inserted_at)
        "issue_asc" -> order_by(query, [b], asc_nulls_last: b.issue_number, asc: b.title)
        "issue_desc" -> order_by(query, [b], desc_nulls_last: b.issue_number, asc: b.title)
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
        "year_asc" -> order_by(query, [s], asc_nulls_last: s.start_year, asc: s.name)
        "year_desc" -> order_by(query, [s], desc_nulls_last: s.start_year, asc: s.name)
        "added_asc" -> order_by(query, [s], asc: s.inserted_at)
        "added_desc" -> order_by(query, [s], desc: s.inserted_at)
        _ -> order_by(query, [s], asc: s.name)
      end

    Repo.all(query) |> Repo.preload(:publishers) |> attach_series_blurhashes()
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
    cover_paths =
      from(bc in BookCover, where: bc.book_id == ^book.id, select: bc.path) |> Repo.all()

    result =
      Repo.transaction(fn ->
        Repo.delete_all(from bc in BookCover, where: bc.book_id == ^book.id)
        Repo.delete!(book)
      end)

    if match?({:ok, _}, result), do: delete_cover_files(cover_paths)
    result
  end

  def purge_series(series) do
    book_ids = from(b in Book, where: b.series_id == ^series.id, select: b.id) |> Repo.all()

    cover_paths =
      from(bc in BookCover, where: bc.book_id in ^book_ids, select: bc.path) |> Repo.all()

    result =
      Repo.transaction(fn ->
        Repo.delete_all(from bc in BookCover, where: bc.book_id in ^book_ids)
        Repo.delete_all(from b in Book, where: b.id in ^book_ids)
        Repo.delete!(series)
      end)

    if match?({:ok, _}, result), do: delete_cover_files(cover_paths)
    result
  end

  def batch_restore_books(ids) do
    from(b in Book, where: b.id in ^ids)
    |> Repo.update_all(set: [deleted_at: nil])
  end

  def batch_purge_books(ids) do
    cover_paths = from(bc in BookCover, where: bc.book_id in ^ids, select: bc.path) |> Repo.all()

    result =
      Repo.transaction(fn ->
        Repo.delete_all(from bc in BookCover, where: bc.book_id in ^ids)
        Repo.delete_all(from b in Book, where: b.id in ^ids)
      end)

    if match?({:ok, _}, result), do: delete_cover_files(cover_paths)
    result
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
    book_ids = from(b in Book, where: b.series_id in ^ids, select: b.id) |> Repo.all()

    cover_paths =
      from(bc in BookCover, where: bc.book_id in ^book_ids, select: bc.path) |> Repo.all()

    result =
      Repo.transaction(fn ->
        Repo.delete_all(from bc in BookCover, where: bc.book_id in ^book_ids)
        Repo.delete_all(from b in Book, where: b.id in ^book_ids)
        Repo.delete_all(from s in Series, where: s.id in ^ids)
      end)

    if match?({:ok, _}, result), do: delete_cover_files(cover_paths)
    result
  end

  defp delete_cover_files(paths) do
    cache_dir =
      Application.get_env(:stashix, :image_cache_dir, "/tmp/stashix/cache/images/resized")

    cached_files =
      case File.ls(cache_dir) do
        {:ok, files} -> files
        _ -> []
      end

    Enum.each(paths, fn path ->
      File.rm(path)
      prefix = :crypto.hash(:md5, path) |> Base.encode16(case: :lower)

      cached_files
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.each(&File.rm(Path.join(cache_dir, &1)))
    end)
  end

  def delete_library(library) do
    book_ids =
      from(b in Book, where: b.library_id == ^library.id, select: b.id) |> Repo.all()

    cover_paths =
      from(bc in BookCover, where: bc.book_id in ^book_ids, select: bc.path) |> Repo.all()

    result =
      Repo.transaction(fn ->
        Repo.delete_all(from bc in BookCover, where: bc.book_id in ^book_ids)
        Repo.delete_all(from b in Book, where: b.library_id == ^library.id)
        Repo.delete_all(from s in Series, where: s.library_id == ^library.id)
        Repo.delete_all(from p in LibraryPermission, where: p.library_id == ^library.id)
        Repo.delete!(library)
      end)

    if match?({:ok, _}, result), do: delete_cover_files(cover_paths)
    result
  end
end
