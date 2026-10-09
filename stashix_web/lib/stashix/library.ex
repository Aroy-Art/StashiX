defmodule Stashix.Library do
  import Ecto.Query
  alias Stashix.Repo

  alias Stashix.Library.{
    Access,
    Library,
    Book,
    BookFile,
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

  @doc "Library by id, raising `Ecto.NoResultsError` unless `access` can read it."
  def get_readable_library!(access, id) do
    case Access.library_ids(access) do
      :all -> Repo.get!(Library, id)
      ids -> Repo.get!(from(l in Library, where: l.id in ^ids), id)
    end
  end

  defp access!(opts), do: Keyword.fetch!(opts, :access)

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
      from b in Access.books(access!(opts)),
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

    books = Repo.all(query)
    populate_source_formats(books)
  end

  defp populate_source_formats([]), do: []

  defp populate_source_formats(books) do
    book_ids = Enum.map(books, & &1.id)

    formats =
      from(bf in BookFile,
        where: bf.book_id in ^book_ids and is_nil(bf.deleted_at),
        select: {bf.book_id, bf.source_format}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(books, fn b -> %{b | source_format: Map.get(formats, b.id)} end)
  end

  def get_book!(id), do: Repo.get!(Book, id)

  @doc "Book by id, raising `Ecto.NoResultsError` unless `access` can see it."
  def get_book!(access, id), do: Repo.get!(Access.books(access), id)

  def get_book_with_series(access, id) do
    files_query = from(bf in BookFile, where: is_nil(bf.deleted_at), order_by: [asc: bf.format])

    get_book!(access, id)
    |> Repo.preload([:series, :cover, :publishers, files: files_query])
  end

  @doc "Book with all MetronInfo detail associations, for the book page's details panel."
  def get_book_details(access, id) do
    get_book!(access, id)
    |> Repo.preload([
      :imprint,
      :external_ids,
      :genres,
      :tags,
      :characters,
      :teams,
      :locations,
      :universes,
      :reprints,
      :prices,
      :urls,
      stories: from(s in Stashix.Library.BookStory, order_by: s.inserted_at),
      story_arcs: from(a in Stashix.Library.BookStoryArc, order_by: a.name),
      credits: [:creator]
    ])
  end

  @doc """
  Series-level details: the series' own extra fields plus the most frequent
  creators, characters, teams, story arcs, genres, tags, locations and
  universes across its live books.
  """
  def series_details(access, series_id, limit \\ 20) do
    series = get_series!(access, series_id) |> Repo.preload([:external_ids, :alternative_names])

    book_ids =
      from(b in Access.books(access), where: b.series_id == ^series_id and is_nil(b.deleted_at), select: b.id)

    top = fn schema ->
      from(r in schema,
        where: r.book_id in subquery(book_ids),
        group_by: r.name,
        select: {r.name, count(r.id)},
        order_by: [desc: count(r.id), asc: r.name],
        limit: ^limit
      )
      |> Repo.all()
    end

    creators =
      from(c in Stashix.Library.BookCredit,
        join: cr in assoc(c, :creator),
        where: c.book_id in subquery(book_ids),
        group_by: [cr.name, c.role, cr.id],
        select: {cr.name, c.role, count(c.id), cr.id}
      )
      |> Repo.all()

    %{
      series: series,
      creators: creators,
      characters: top.(Stashix.Library.BookCharacter),
      teams: top.(Stashix.Library.BookTeam),
      arcs: top.(Stashix.Library.BookStoryArc),
      genres: top.(Stashix.Library.BookGenre),
      tags: top.(Stashix.Library.BookTag),
      locations: top.(Stashix.Library.BookLocation),
      universes: top.(Stashix.Library.BookUniverse)
    }
  end

  def get_adjacent_books(_access, %{series_id: nil}), do: {nil, nil}

  def get_adjacent_books(_access, %{series_id: _series_id, issue_number: nil}), do: {nil, nil}

  def get_adjacent_books(access, %{id: id, series_id: series_id, issue_number: _issue_number}) do
    siblings =
      from(b in Access.books(access),
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
    access = access!(opts)

    query =
      from s in Access.series(access),
        left_join: b in ^Access.books(access),
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

    Repo.all(query) |> Repo.preload(:publishers) |> attach_series_blurhashes(access)
  end

  def get_series!(id), do: Repo.get!(Series, id)

  @doc "Series by id, raising `Ecto.NoResultsError` unless `access` can see it."
  def get_series!(access, id), do: Repo.get!(Access.series(access), id)

  def get_series_with_books(access, id) do
    books_query =
      from(b in Access.books(access),
        where: is_nil(b.deleted_at),
        order_by: [asc: b.issue_number]
      )

    get_series!(access, id) |> Repo.preload([:publishers, books: {books_query, [:cover]}])
  end

  @doc "Saves reading progress; `{:error, :not_found}` unless `access` can see the book."
  def update_progress(access, user_id, book_id, page) do
    if Repo.exists?(from(b in Access.books(access), where: b.id == ^book_id)),
      do: put_progress(user_id, book_id, page),
      else: {:error, :not_found}
  end

  defp put_progress(user_id, book_id, page) do
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

  def in_progress_books(access, user_id, limit \\ 20) do
    results =
      from(rp in ReadingProgress,
        where: rp.user_id == ^user_id and rp.current_page > 0,
        join: b in ^Access.books(access),
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
        left_join: b in ^Access.books(access),
        on: b.series_id == s.id and is_nil(b.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)}

    loaded_map =
      Repo.preload(books, [:cover, [series: series_query]]) |> Map.new(&{&1.id, &1})

    Enum.map(results, fn {book, current_page} ->
      %{book: loaded_map[book.id], current_page: current_page}
    end)
  end

  def next_issue_books(access, user_id, limit \\ 20) do
    completed_by_series =
      from(rp in ReadingProgress,
        where: rp.user_id == ^user_id and rp.current_page > 0,
        join: b in ^Access.books(access),
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

      from(b in Access.books(access),
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

    from(b in Access.books(access!(opts)),
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
    access = access!(opts)

    issues =
      from(b in Access.books(access),
        where:
          fragment("search_vec @@ plainto_tsquery('english', ?)", ^query_string) and
            is_nil(b.deleted_at) and b.type == "issue",
        order_by: fragment("ts_rank(search_vec, plainto_tsquery('english', ?)) DESC", ^query_string),
        preload: [:cover, :series],
        limit: ^limit
      )
      |> Repo.all()

    books =
      from(b in Access.books(access),
        where:
          fragment("search_vec @@ plainto_tsquery('english', ?)", ^query_string) and
            is_nil(b.deleted_at) and b.type == "standalone",
        order_by: fragment("ts_rank(search_vec, plainto_tsquery('english', ?)) DESC", ^query_string),
        preload: [:cover, :series],
        limit: ^limit
      )
      |> Repo.all()

    pattern = "%#{String.replace(query_string, "%", "\\%")}%"

    series =
      from(s in Access.series(access),
        left_join: b in ^Access.books(access),
        on: b.series_id == s.id and is_nil(b.deleted_at),
        where: ilike(s.name, ^pattern) and is_nil(s.deleted_at),
        group_by: s.id,
        order_by: [asc: s.name],
        select: %{s | issue_count: count(b.id)},
        limit: ^limit
      )
      |> Repo.all()
      |> attach_series_blurhashes(access)

    %{series: series, issues: issues, books: books}
  end

  # ---------------------------------------------------------------------------
  # Filtered search (search page)
  #
  # `filters` is a map with any of:
  #   :q            - free text (full-text on books, ilike on series names)
  #   :types        - list of book types ("issue", "standalone")
  #   :year_from    - integer, inclusive
  #   :year_to      - integer, inclusive
  #   :age_ratings  - list of age rating atoms
  #   :library_id   - library UUID
  #   :publisher_id - canonical publisher UUID (aliases are included)
  #   :genre / :tag / :character / :team / :location - lists of names; a book
  #                   must have all of them
  #   :read_status  - "unread" | "in_progress" | "read" (requires :user_id)
  #   :user_id      - current user, for read status
  #   :sort         - "relevance" | "title_asc" | "title_desc" | "year_asc" |
  #                   "year_desc" | "added_desc" | "added_asc"
  # ---------------------------------------------------------------------------

  def search_filtered_books(filters, opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    base = filtered_books_query(filters, access!(opts))

    total = Repo.aggregate(base, :count, :id)

    books =
      base
      |> sort_filtered_books(filters)
      |> limit(^limit)
      |> offset(^offset)
      |> preload([:cover, :series])
      |> Repo.all()

    {books, total}
  end

  def search_filtered_series(filters, opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    access = access!(opts)
    base = filtered_series_query(filters, access)

    total = Repo.aggregate(base, :count, :id)

    series =
      from([series: s] in base,
        left_join: b in ^Access.books(access),
        on: b.series_id == s.id and is_nil(b.deleted_at),
        group_by: s.id,
        select: %{s | issue_count: count(b.id)},
        limit: ^limit,
        offset: ^offset
      )
      |> sort_filtered_series(filters)
      |> Repo.all()
      |> attach_series_blurhashes(access)

    {series, total}
  end

  @doc """
  `[{year, book_count}]` for every release year that has books, ascending.
  Year is the book's year, falling back to its cover date.
  """
  def book_year_counts(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at),
      where: not is_nil(fragment("COALESCE(?, EXTRACT(YEAR FROM ?)::int)", b.year, b.cover_date)),
      group_by: fragment("1"),
      order_by: fragment("1"),
      select: {fragment("COALESCE(?, EXTRACT(YEAR FROM ?)::int)", b.year, b.cover_date), count(b.id)}
    )
    |> Repo.all()
  end

  @doc """
  Creators whose name contains `term`, prefix matches first, then by how many
  (non-deleted) books credit them. Returns `[%{id, name, credits}]`.

  Options: `:limit` (default 8), `:exclude` (creator ids to leave out).
  """
  def search_creators(term, opts \\ []) do
    term = String.trim(term)
    limit = Keyword.get(opts, :limit, 8)
    exclude = Keyword.get(opts, :exclude, [])
    access = access!(opts)

    if term == "" do
      []
    else
      from(cr in Stashix.Library.Creator,
        join: c in assoc(cr, :credits),
        join: b in ^Access.books(access),
        on: b.id == c.book_id and is_nil(b.deleted_at),
        where: ilike(cr.name, ^like_pattern(term)) and cr.id not in ^exclude,
        group_by: cr.id,
        order_by: [
          desc: fragment("? ILIKE ?", cr.name, ^(like_escape(term) <> "%")),
          desc: count(b.id, :distinct),
          asc: cr.name
        ],
        limit: ^limit,
        select: %{id: cr.id, name: cr.name, credits: count(b.id, :distinct)}
      )
      |> Repo.all()
    end
  end

  @doc "Creators for `ids`, in the order given (unknown ids are dropped)."
  def get_creators([]), do: []

  def get_creators(ids) do
    by_id =
      from(cr in Stashix.Library.Creator, where: cr.id in ^ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1)
  end

  @book_facets %{
    genre: Stashix.Library.BookGenre,
    tag: Stashix.Library.BookTag,
    character: Stashix.Library.BookCharacter,
    team: Stashix.Library.BookTeam,
    location: Stashix.Library.BookLocation
  }

  @doc "Book facets that can be filtered by name in search."
  def book_facets, do: Map.keys(@book_facets)

  @doc "Whether any book has an entry for the facet at all."
  def facet_any?(facet), do: Repo.exists?(Map.fetch!(@book_facets, facet))

  @doc """
  Names in a book facet (`:genre`, `:tag`, `:character`, `:team`, `:location`) containing
  `term`, prefix matches first, then by how many (non-deleted) books use them.
  Returns `[%{name, books}]`.

  Options: `:limit` (default 8), `:exclude` (names to leave out).
  """
  def search_facet_names(facet, term, opts \\ []) do
    term = String.trim(term)
    limit = Keyword.get(opts, :limit, 8)
    exclude = Keyword.get(opts, :exclude, [])
    access = access!(opts)

    if term == "" do
      []
    else
      from(f in Map.fetch!(@book_facets, facet),
        join: b in ^Access.books(access),
        on: b.id == f.book_id and is_nil(b.deleted_at),
        where: ilike(f.name, ^like_pattern(term)) and f.name not in ^exclude,
        group_by: f.name,
        order_by: [
          desc: fragment("? ILIKE ?", f.name, ^(like_escape(term) <> "%")),
          desc: count(b.id, :distinct),
          asc: f.name
        ],
        limit: ^limit,
        select: %{name: f.name, books: count(b.id, :distinct)}
      )
      |> Repo.all()
    end
  end

  defp filtered_books_query(filters, access) do
    query = from(b in Access.books(access), as: :book, where: is_nil(b.deleted_at))

    query =
      case filters[:q] do
        q when is_binary(q) and q != "" ->
          pattern = like_pattern(q)

          where(
            query,
            [b],
            fragment("search_vec @@ plainto_tsquery('english', ?)", ^q) or
              exists(credit_match_query(name_pattern: pattern))
          )

        _ ->
          query
      end

    query =
      case filters[:types] do
        [_ | _] = types -> where(query, [b], b.type in ^types)
        _ -> query
      end

    query
    |> filter_book_year(filters[:year_from], filters[:year_to])
    |> filter_book_attrs(filters)
    |> filter_read_status(filters[:read_status], filters[:user_id])
  end

  # Credits on the parent book (bound as :book), narrowed by any of
  # :name_pattern (ilike on creator name), :creator_id and :role.
  defp credit_match_query(opts) do
    query =
      from(c in Stashix.Library.BookCredit,
        join: cr in assoc(c, :creator),
        where: c.book_id == parent_as(:book).id,
        select: 1
      )

    query =
      if pattern = opts[:name_pattern],
        do: where(query, [_c, cr], ilike(cr.name, ^pattern)),
        else: query

    query =
      if creator_id = opts[:creator_id],
        do: where(query, [c], c.creator_id == ^creator_id),
        else: query

    query =
      case opts[:creator_ids] do
        [_ | _] = ids -> where(query, [c], c.creator_id in ^ids)
        _ -> query
      end

    if role = opts[:role], do: where(query, [c], c.role == ^role), else: query
  end

  defp like_pattern(term), do: "%#{like_escape(term)}%"

  defp like_escape(term), do: String.replace(term, ~r/[\\%_]/, "\\\\\\0")

  # "all": every creator is credited on the book (each in `role`, if given).
  # "any": at least one of them is.
  defp filter_book_creators(query, [], _match, nil), do: query

  defp filter_book_creators(query, [], _match, role),
    do: where(query, exists(credit_match_query(role: role)))

  defp filter_book_creators(query, ids, "any", role),
    do: where(query, exists(credit_match_query(creator_ids: ids, role: role)))

  defp filter_book_creators(query, ids, _all, role) do
    Enum.reduce(ids, query, fn id, q ->
      where(q, exists(credit_match_query(creator_id: id, role: role)))
    end)
  end

  # Shared by books and series-with-matching-books: age rating, library,
  # publisher, genre/tag/character/team/location, creator/role. Expects the book binding to be named :book.
  defp filter_book_attrs(query, filters) do
    query = filter_book_creators(query, filters[:creator_ids] || [], filters[:creator_match], filters[:role])

    query =
      case filters[:age_ratings] do
        [_ | _] = ratings -> where(query, [book: b], b.age_rating in ^ratings)
        _ -> query
      end

    query =
      if filters[:library_id],
        do: where(query, [book: b], b.library_id == ^filters[:library_id]),
        else: query

    query =
      if filters[:publisher_id] do
        bins = publisher_id_bins(filters[:publisher_id])

        where(
          query,
          [book: b],
          exists(
            from(bp in "book_publishers",
              where: bp.book_id == parent_as(:book).id and bp.publisher_id in ^bins,
              select: 1
            )
          )
        )
      else
        query
      end

    Enum.reduce(@book_facets, query, fn {key, schema}, query ->
      filter_book_named(query, schema, filters[key])
    end)
  end

  # Keep books that have a row in `schema` (genres, tags, …) for every given name.
  defp filter_book_named(query, schema, names) do
    names
    |> List.wrap()
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.reduce(query, fn name, query ->
      where(
        query,
        [book: b],
        exists(from(r in schema, where: r.book_id == parent_as(:book).id and r.name == ^name, select: 1))
      )
    end)
  end

  defp filter_book_year(query, nil, nil), do: query

  defp filter_book_year(query, from_year, to_year) do
    year = dynamic([book: b], fragment("COALESCE(?, EXTRACT(YEAR FROM ?)::int)", b.year, b.cover_date))
    query = if from_year, do: where(query, ^dynamic(^year >= ^from_year)), else: query
    if to_year, do: where(query, ^dynamic(^year <= ^to_year)), else: query
  end

  defp filter_read_status(query, status, user_id)
       when status in ["unread", "in_progress", "read"] and not is_nil(user_id) do
    query =
      join(query, :left, [book: b], rp in ReadingProgress,
        as: :progress,
        on: rp.book_id == b.id and rp.user_id == ^user_id
      )

    case status do
      "unread" ->
        where(query, [progress: rp], is_nil(rp.id) or rp.current_page == 0)

      "in_progress" ->
        where(
          query,
          [book: b, progress: rp],
          rp.current_page > 0 and rp.current_page < b.page_count - 1
        )

      "read" ->
        where(
          query,
          [book: b, progress: rp],
          not is_nil(rp.id) and b.page_count > 0 and rp.current_page >= b.page_count - 1
        )
    end
  end

  defp filter_read_status(query, _status, _user_id), do: query

  defp sort_filtered_books(query, filters) do
    case {filters[:sort], filters[:q]} do
      {"relevance", q} when is_binary(q) and q != "" ->
        order_by(query, [b],
          desc: fragment("ts_rank(search_vec, plainto_tsquery('english', ?))", ^q),
          asc: b.title
        )

      {"title_desc", _} ->
        order_by(query, [b], desc: b.title)

      {"year_asc", _} ->
        order_by(query, [b], asc_nulls_last: b.year, asc: b.title)

      {"year_desc", _} ->
        order_by(query, [b], desc_nulls_last: b.year, asc: b.title)

      {"added_desc", _} ->
        order_by(query, [b], desc: b.inserted_at)

      {"added_asc", _} ->
        order_by(query, [b], asc: b.inserted_at)

      _ ->
        order_by(query, [b], asc: b.title, asc_nulls_last: b.issue_number)
    end
  end

  defp filtered_series_query(filters, access) do
    query = from(s in Access.series(access), as: :series, where: is_nil(s.deleted_at))

    query =
      case filters[:q] do
        q when is_binary(q) and q != "" ->
          pattern = like_pattern(q)

          credited_book =
            from(b in Access.books(access),
              as: :book,
              where: b.series_id == parent_as(:series).id and is_nil(b.deleted_at),
              where: exists(credit_match_query(name_pattern: pattern)),
              select: 1
            )

          where(query, [s], ilike(s.name, ^pattern) or exists(credited_book))

        _ ->
          query
      end

    query =
      if filters[:library_id],
        do: where(query, [s], s.library_id == ^filters[:library_id]),
        else: query

    query =
      if filters[:year_from],
        do: where(query, [s], s.start_year >= ^filters[:year_from]),
        else: query

    query =
      if filters[:year_to],
        do: where(query, [s], s.start_year <= ^filters[:year_to]),
        else: query

    query =
      case filters[:series_status] do
        "ongoing" -> where(query, [s], s.ongoing == true)
        "completed" -> where(query, [s], s.ongoing == false)
        _ -> query
      end

    # Book-level filters: keep series that contain at least one matching book.
    book_filters =
      Map.take(filters, [:age_ratings, :publisher_id, :creator_ids, :creator_match, :role | book_facets()])

    if Enum.any?(book_filters, fn {k, v} -> k != :creator_match and v not in [nil, []] end) do
      book_query =
        from(b in Access.books(access),
          as: :book,
          where: b.series_id == parent_as(:series).id and is_nil(b.deleted_at),
          select: 1
        )
        |> filter_book_attrs(book_filters)

      where(query, [s], exists(book_query))
    else
      query
    end
  end

  defp sort_filtered_series(query, filters) do
    case filters[:sort] do
      "title_desc" -> order_by(query, [s], desc: s.name)
      "year_asc" -> order_by(query, [s], asc_nulls_last: s.start_year, asc: s.name)
      "year_desc" -> order_by(query, [s], desc_nulls_last: s.start_year, asc: s.name)
      "added_desc" -> order_by(query, [s], desc: s.inserted_at)
      "added_asc" -> order_by(query, [s], asc: s.inserted_at)
      _ -> order_by(query, [s], asc: s.name)
    end
  end

  def get_series_cover(access, series_id) do
    series = get_series!(access, series_id)

    # The folder cover is unrated, so it is only served to users who can see
    # every book of the series; others get the cover of a book they can see.
    folder_cover =
      series.path && sees_whole_series?(access, series_id) &&
        Enum.find_value(~w(cover.jpg cover.jpeg cover.png cover.webp), fn name ->
          path = Path.join(series.path, name)
          if File.exists?(path), do: path
        end)

    folder_cover ||
      from(bc in BookCover,
        join: b in ^Access.books(access),
        on: b.id == bc.book_id,
        where: b.series_id == ^series_id and is_nil(b.deleted_at),
        order_by: [asc_nulls_last: b.issue_number, asc: b.inserted_at],
        limit: 1,
        select: bc.path
      )
      |> Repo.one()
  end

  defp sees_whole_series?(%Access{all?: true}, _series_id), do: true

  defp sees_whole_series?(access, series_id) do
    visible = from(b in Access.books(access), select: b.id)

    not Repo.exists?(
      from(b in Book,
        where: b.series_id == ^series_id and is_nil(b.deleted_at) and b.id not in subquery(visible)
      )
    )
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
    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      join: s in Series,
      on: s.id == b.series_id,
      where: b.library_id == ^library_id and bf.file_hash in ^hashes and is_nil(bf.deleted_at),
      select: {bf.file_hash, s}
    )
    |> Repo.all()
    |> Map.new()
  end

  def find_series_by_book_hashes(library_id, hashes) do
    series_id =
      from(bf in BookFile,
        join: b in Book,
        on: b.id == bf.book_id,
        where: b.library_id == ^library_id and bf.file_hash in ^hashes and is_nil(bf.deleted_at),
        group_by: b.series_id,
        order_by: [desc: count(bf.id)],
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
        |> Repo.insert(
          on_conflict: [set: Map.to_list(Map.take(attrs, [:name, :start_year, :end_year, :ongoing]))],
          conflict_target: [:library_id, :path]
        )

      series ->
        series
        |> Series.changeset(Map.take(attrs, [:name, :start_year, :end_year, :ongoing, :path]))
        |> Repo.update()
    end
  end

  def update_series(series, attrs) do
    {publisher_ids, series_attrs} = Map.pop(attrs, "publisher_ids")

    changeset = Series.changeset(series, series_attrs)

    changeset =
      if publisher_ids do
        ids = Enum.reject(publisher_ids, &(&1 == ""))
        publishers = Repo.all(from p in Publisher, where: p.id in ^ids)
        Ecto.Changeset.put_assoc(changeset, :publishers, publishers)
      else
        changeset
      end

    Repo.update(changeset)
  end

  @doc """
  Overwrites the age rating of every non-deleted book in the series.
  With `only_unknown: true`, only books rated `:unknown` (or unset) are touched.
  Returns `{:ok, book_ids}` for the books that were updated.
  """
  def set_series_age_rating(series_id, rating, opts \\ []) when is_binary(rating) do
    case Enum.find(Ecto.Enum.values(Book, :age_rating), &(Atom.to_string(&1) == rating)) do
      nil ->
        {:error, :invalid_age_rating}

      atom ->
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        query =
          from(b in Book,
            where: b.series_id == ^series_id and is_nil(b.deleted_at),
            select: b.id
          )

        query =
          if opts[:only_unknown],
            do: where(query, [b], b.age_rating == :unknown or is_nil(b.age_rating)),
            else: query

        {_, ids} = Repo.update_all(query, set: [age_rating: atom, updated_at: now])

        {:ok, ids}
    end
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

  def create_book_file(attrs) do
    %BookFile{}
    |> BookFile.changeset(attrs)
    |> Repo.insert()
  end

  def update_book_file(book_file, attrs) do
    book_file
    |> BookFile.changeset(attrs)
    |> Repo.update()
  end

  def get_book_file_by_path(path) do
    Repo.get_by(BookFile, path: path)
  end

  def get_book_file_by_hash(hash) do
    from(bf in BookFile, where: bf.file_hash == ^hash and is_nil(bf.deleted_at), limit: 1)
    |> Repo.one()
  end

  def get_book_files(book_id) do
    from(bf in BookFile, where: bf.book_id == ^book_id and is_nil(bf.deleted_at))
    |> Repo.all()
  end

  @supported_extensions ~w(.cbz .cbr .cb7 .epub .pdf)

  def get_book_by_stem(dir, stem) do
    candidates = Enum.map(@supported_extensions, &Path.join(dir, stem <> &1))

    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: bf.path in ^candidates and is_nil(bf.deleted_at) and is_nil(b.deleted_at),
      limit: 1,
      select: b
    )
    |> Repo.one()
  end

  def get_preferred_book_file(book, format \\ nil) do
    format_priority = [:cbz, :cbr, :cb7, :epub, :pdf]

    files =
      case book.files do
        %Ecto.Association.NotLoaded{} ->
          from(bf in BookFile,
            where: bf.book_id == ^book.id and is_nil(bf.deleted_at),
            order_by: [asc: bf.format]
          )
          |> Repo.all()

        files ->
          files
      end

    if format do
      fmt = if is_atom(format), do: format, else: String.to_existing_atom(to_string(format))
      Enum.find(files, &(&1.format == fmt)) || List.first(files)
    else
      Enum.min_by(
        files,
        &Enum.find_index(format_priority, fn f -> f == &1.format end),
        fn -> nil end
      )
    end
  end

  def get_publisher!(id), do: Repo.get!(Publisher, id)

  def get_publisher_with_aliases!(access, id) do
    Repo.get!(visible_publishers(access), id) |> Repo.preload([:aliases, :canonical])
  end

  # Publishers credited on a book or series `access` can see, plus the
  # canonical publishers of those (so a master shows when only an alias is used).
  defp visible_publishers(%Access{all?: true}), do: from(p in Publisher)

  defp visible_publishers(access) do
    book_pubs =
      from(bp in "book_publishers",
        join: b in ^Access.books(access),
        on: b.id == bp.book_id and is_nil(b.deleted_at),
        select: type(bp.publisher_id, :binary_id)
      )

    series_pubs =
      from(sp in "series_publishers",
        join: s in subquery(Access.series(access)),
        on: s.id == sp.series_id and is_nil(s.deleted_at),
        select: type(sp.publisher_id, :binary_id)
      )

    used = union(book_pubs, ^series_pubs)

    masters =
      from(p in Publisher,
        where: p.id in subquery(used) and not is_nil(p.canonical_publisher_id),
        select: p.canonical_publisher_id
      )

    from(p in Publisher, where: p.id in subquery(used) or p.id in subquery(masters))
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
    access = access!(opts)
    pub_bins = publisher_id_bins(publisher_id)

    query =
      from s in Access.series(access),
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

    Repo.all(query) |> attach_series_blurhashes(access)
  end

  def count_publisher_series(access, publisher_id) do
    pub_bins = publisher_id_bins(publisher_id)

    from(s in Access.series(access),
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
      from b in Access.books(access!(opts)),
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

  def count_publisher_books(access, publisher_id, type) do
    pub_bins = publisher_id_bins(publisher_id)

    from(b in Access.books(access),
      join: bp in "book_publishers",
      on: bp.book_id == b.id,
      where: bp.publisher_id in ^pub_bins and is_nil(b.deleted_at) and b.type == ^type,
      distinct: true
    )
    |> Repo.aggregate(:count, :id)
  end

  def list_publishers(access) do
    from(p in visible_publishers(access),
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

  def count_publishers(access) do
    from(p in visible_publishers(access), where: is_nil(p.canonical_publisher_id) and not p.hidden)
    |> Repo.aggregate(:count, :id)
  end

  def list_publishers_paginated(opts \\ []) do
    limit = Keyword.get(opts, :limit, 24)
    offset = Keyword.get(opts, :offset, 0)

    from(p in visible_publishers(access!(opts)),
      where: is_nil(p.canonical_publisher_id) and not p.hidden,
      order_by: [asc: p.name],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  def publisher_stats(_access, publisher_ids) when publisher_ids == [], do: %{}

  def publisher_stats(access, publisher_ids) do
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
        join: s in subquery(Access.series(access)),
        on: s.id == sp.series_id,
        where: sp.publisher_id in ^all_bins and is_nil(s.deleted_at),
        group_by: sp.publisher_id,
        select: {sp.publisher_id, count(s.id)}
      )
      |> Repo.all()
      |> sum_by_master.()

    books_counts =
      from(bp in "book_publishers",
        join: b in ^Access.books(access),
        on: b.id == bp.book_id,
        where: bp.publisher_id in ^all_bins and is_nil(b.deleted_at) and b.type == "standalone",
        group_by: bp.publisher_id,
        select: {bp.publisher_id, count(b.id)}
      )
      |> Repo.all()
      |> sum_by_master.()

    issues_counts =
      from(bp in "book_publishers",
        join: b in ^Access.books(access),
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

  def publisher_sample_covers(_access, publisher_ids) when publisher_ids == [], do: %{}

  def publisher_sample_covers(access, publisher_ids) do
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
      join: b in ^Access.books(access),
      on: b.id == bp.book_id,
      join: c in BookCover,
      on: c.book_id == b.id,
      where: bp.publisher_id in ^all_bins and is_nil(b.deleted_at),
      select: {bp.publisher_id, bp.book_id, c.blurhash}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {pub_id, _, _} -> Map.get(id_to_master, Ecto.UUID.cast!(pub_id)) end,
      fn {_, book_id, blurhash} -> {Ecto.UUID.cast!(book_id), blurhash} end
    )
    |> Enum.into(%{}, fn {master_id, covers} ->
      {master_id, covers |> Enum.uniq_by(&elem(&1, 0)) |> Enum.sort_by(&elem(&1, 0)) |> Enum.take(5)}
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
    {publisher_ids, book_attrs} = Map.pop(attrs, "publisher_ids")

    changeset = Book.changeset(book, book_attrs)

    changeset =
      if publisher_ids do
        ids = Enum.reject(publisher_ids, &(&1 == ""))
        publishers = Repo.all(from p in Publisher, where: p.id in ^ids)
        Ecto.Changeset.put_assoc(changeset, :publishers, publishers)
      else
        changeset
      end

    Repo.update(changeset)
  end

  def load_books_cache(library_id) do
    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: b.library_id == ^library_id,
      select: {bf.path, %{last_modified: bf.last_modified, deleted_at: bf.deleted_at, file_hash: bf.file_hash}}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_book_by_path(path) do
    case from(bf in BookFile, where: bf.path == ^path, select: bf.book_id, limit: 1)
         |> Repo.one() do
      nil -> nil
      book_id -> Repo.get(Book, book_id)
    end
  end

  def get_book_by_hash(hash) do
    case from(bf in BookFile,
           where: bf.file_hash == ^hash and is_nil(bf.deleted_at),
           select: bf.book_id,
           limit: 1
         )
         |> Repo.one() do
      nil -> nil
      book_id -> Repo.get(Book, book_id)
    end
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

  def series_cover_blurhash_map(_access, []), do: %{}

  def series_cover_blurhash_map(access, series_ids) do
    from(bc in BookCover,
      join: b in ^Access.books(access),
      on: b.id == bc.book_id and is_nil(b.deleted_at),
      where: b.series_id in ^series_ids,
      distinct: [asc: b.series_id],
      order_by: [asc: b.series_id, asc_nulls_last: b.issue_number, asc: b.inserted_at],
      select: {b.series_id, bc.blurhash}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp attach_series_blurhashes([], _access), do: []

  defp attach_series_blurhashes(series, access) do
    ids = Enum.map(series, & &1.id)
    bh_map = series_cover_blurhash_map(access, ids)
    stack_map = series_stack_map(access, ids)

    Enum.map(series, fn s ->
      %{s | cover_blurhash: Map.get(bh_map, s.id), stack_book_ids: Map.get(stack_map, s.id, [])}
    end)
  end

  @doc "Ids of up to `count` books the user may see that have a cover, picked at random."
  def random_cover_book_ids(access, count) do
    from(bc in BookCover,
      join: b in ^Access.books(access),
      on: b.id == bc.book_id and is_nil(b.deleted_at),
      where: not is_nil(bc.path),
      order_by: fragment("RANDOM()"),
      limit: ^count,
      select: b.id
    )
    |> Repo.all()
  end

  @doc """
  For each series, the ids of its second and third issues that have a cover
  (the first is the series cover itself), in reading order.
  """
  def series_stack_map(_access, []), do: %{}

  def series_stack_map(access, series_ids) do
    ranked =
      from bc in BookCover,
        join: b in ^Access.books(access),
        on: b.id == bc.book_id and is_nil(b.deleted_at),
        where: b.series_id in ^series_ids and not is_nil(bc.path),
        select: %{
          book_id: b.id,
          series_id: b.series_id,
          rank:
            over(row_number(),
              partition_by: b.series_id,
              order_by: [asc_nulls_last: b.issue_number, asc: b.inserted_at]
            )
        }

    from(r in subquery(ranked),
      where: r.rank in [2, 3],
      order_by: [asc: r.rank],
      select: {r.series_id, r.book_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  def list_user_permissions(user_id) do
    from(p in LibraryPermission, where: p.user_id == ^user_id)
    |> Repo.all()
    |> Map.new(&{&1.library_id, &1})
  end

  def set_library_permission(attrs) do
    result =
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

    # Open LiveViews hold the access computed at mount; make them remount.
    with {:ok, permission} <- result do
      Stashix.Accounts.disconnect_sessions(permission.user_id)
      {:ok, permission}
    end
  end

  def count_books(access, library_id) do
    Repo.aggregate(
      from(b in Access.books(access),
        where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "standalone"
      ),
      :count,
      :id
    )
  end

  def count_series(access, library_id) do
    Repo.aggregate(
      from(s in Access.series(access), where: s.library_id == ^library_id and is_nil(s.deleted_at)),
      :count,
      :id
    )
  end

  def count_issues(access, library_id) do
    Repo.aggregate(
      from(b in Access.books(access),
        where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "issue"
      ),
      :count,
      :id
    )
  end

  def total_size_for_series(access, series_id) do
    result =
      from(bf in BookFile,
        join: b in ^Access.books(access),
        on: b.id == bf.book_id,
        where: b.series_id == ^series_id and is_nil(b.deleted_at) and is_nil(bf.deleted_at)
      )
      |> Repo.aggregate(:sum, :file_size)

    case result do
      nil -> 0
      %Decimal{} = d -> Decimal.to_integer(d)
      n -> n
    end
  end

  def total_size(access, library_id) do
    result =
      from(bf in BookFile,
        join: b in ^Access.books(access),
        on: b.id == bf.book_id,
        where: b.library_id == ^library_id and is_nil(b.deleted_at) and is_nil(bf.deleted_at)
      )
      |> Repo.aggregate(:sum, :file_size)

    case result do
      nil -> 0
      %Decimal{} = d -> Decimal.to_integer(d)
      n -> n
    end
  end

  def recent_books(access, library_id, limit \\ 10, type \\ nil) do
    query =
      from b in Access.books(access),
        where: b.library_id == ^library_id and is_nil(b.deleted_at),
        order_by: [desc: b.inserted_at],
        limit: ^limit,
        preload: [:cover]

    query =
      if type, do: where(query, [b], b.type == ^type), else: query

    Repo.all(query)
  end

  def recent_series(access, library_id, limit \\ 10) do
    from(s in Access.series(access),
      left_join: b in ^Access.books(access),
      on: b.series_id == s.id and is_nil(b.deleted_at),
      where: s.library_id == ^library_id and is_nil(s.deleted_at),
      group_by: s.id,
      order_by: [desc: s.inserted_at],
      limit: ^limit,
      select: %{s | issue_count: count(b.id)}
    )
    |> Repo.all()
    |> attach_series_blurhashes(access)
  end

  def recent_issues(access, library_id, limit \\ 10) do
    from(b in Access.books(access),
      where: b.library_id == ^library_id and is_nil(b.deleted_at) and b.type == "issue",
      order_by: [desc: b.inserted_at],
      limit: ^limit,
      preload: [:cover]
    )
    |> Repo.all()
  end

  def mark_orphaned_books(library_id, scanned_paths) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: b.library_id == ^library_id and is_nil(bf.deleted_at) and bf.path not in ^scanned_paths
    )
    |> Repo.update_all(set: [deleted_at: now])

    active_book_ids = from(bf in BookFile, where: is_nil(bf.deleted_at), select: bf.book_id)

    from(b in Book,
      where:
        b.library_id == ^library_id and is_nil(b.deleted_at) and
          b.id not in subquery(active_book_ids)
    )
    |> Repo.update_all(set: [deleted_at: now])
  end

  def mark_orphaned_series_books(series_id, scanned_paths) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    from(bf in BookFile,
      join: b in Book,
      on: b.id == bf.book_id,
      where: b.series_id == ^series_id and is_nil(bf.deleted_at) and bf.path not in ^scanned_paths
    )
    |> Repo.update_all(set: [deleted_at: now])

    active_book_ids = from(bf in BookFile, where: is_nil(bf.deleted_at), select: bf.book_id)

    from(b in Book,
      where:
        b.series_id == ^series_id and is_nil(b.deleted_at) and
          b.id not in subquery(active_book_ids)
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
      from b in Access.books(access!(opts)),
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
    access = access!(opts)

    query =
      from s in Series,
        where: is_nil(s.deleted_at) and s.id in subquery(series_with_issues(access)),
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
      from b in Access.books(access),
        where: is_nil(b.deleted_at) and b.type == "issue",
        order_by: [asc_nulls_last: b.issue_number, asc: b.title]

    Repo.all(query) |> Repo.preload(books: {issues_query, [:cover]})
  end

  def count_series_for_issues(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query =
      from s in Series,
        where: is_nil(s.deleted_at) and s.id in subquery(series_with_issues(access!(opts)))

    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query
    Repo.aggregate(query, :count, :id)
  end

  defp series_with_issues(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at) and b.type == "issue" and not is_nil(b.series_id),
      select: b.series_id
    )
  end

  def list_ungrouped_issues(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query =
      from b in Access.books(access!(opts)),
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
      from b in Access.books(access!(opts)),
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

    query = from b in Access.books(access!(opts)), where: is_nil(b.deleted_at)
    query = if type, do: where(query, [b], b.type == ^type), else: query
    query = if library_id, do: where(query, [b], b.library_id == ^library_id), else: query

    Repo.aggregate(query, :count, :id)
  end

  def list_all_series(opts \\ []) do
    limit = Keyword.get(opts, :limit, 48)
    offset = Keyword.get(opts, :offset, 0)
    sort = Keyword.get(opts, :sort, "title_asc")
    library_id = Keyword.get(opts, :library_id)
    access = access!(opts)

    query =
      from s in Access.series(access),
        left_join: b in ^Access.books(access),
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

    Repo.all(query) |> Repo.preload(:publishers) |> attach_series_blurhashes(access)
  end

  def count_all_series(opts \\ []) do
    library_id = Keyword.get(opts, :library_id)

    query = from s in Access.series(access!(opts)), where: is_nil(s.deleted_at)
    query = if library_id, do: where(query, [s], s.library_id == ^library_id), else: query

    Repo.aggregate(query, :count, :id)
  end

  def list_all_deleted_books do
    files_query = from(bf in BookFile, order_by: [asc: bf.format])

    from(b in Book,
      where: not is_nil(b.deleted_at),
      preload: [:series, :cover, :library, files: ^files_query],
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
    Repo.transaction(fn ->
      from(bf in BookFile, where: bf.book_id == ^book.id)
      |> Repo.update_all(set: [deleted_at: nil])

      book |> Book.changeset(%{deleted_at: nil}) |> Repo.update!()
    end)
  end

  def restore_series(series) do
    Repo.transaction(fn ->
      book_ids =
        from(b in Book, where: b.series_id == ^series.id, select: b.id) |> Repo.all()

      from(bf in BookFile, where: bf.book_id in ^book_ids)
      |> Repo.update_all(set: [deleted_at: nil])

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
    from(bf in BookFile, where: bf.book_id in ^ids)
    |> Repo.update_all(set: [deleted_at: nil])

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
      book_ids = from(b in Book, where: b.series_id in ^ids, select: b.id) |> Repo.all()

      from(bf in BookFile, where: bf.book_id in ^book_ids)
      |> Repo.update_all(set: [deleted_at: nil])

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

  # Stats queries (across the libraries `access` can see)

  def stats_books_by_year(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at) and not is_nil(b.year),
      group_by: b.year,
      order_by: b.year,
      select: {b.year, count(b.id)}
    )
    |> Repo.all()
  end

  def stats_books_by_type(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at),
      group_by: b.type,
      select: {b.type, count(b.id)}
    )
    |> Repo.all()
  end

  def stats_added_by_month(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at),
      group_by: fragment("to_char(?, 'YYYY-MM')", b.inserted_at),
      order_by: fragment("to_char(?, 'YYYY-MM')", b.inserted_at),
      select: {fragment("to_char(?, 'YYYY-MM')", b.inserted_at), count(b.id)}
    )
    |> Repo.all()
  end

  def stats_reading_progress(access, user_id) do
    total =
      from(b in Access.books(access), where: is_nil(b.deleted_at), select: count(b.id))
      |> Repo.one()

    if total == 0 do
      %{total: 0, unread: 0, in_progress: 0, completed: 0}
    else
      progress_rows =
        from(rp in ReadingProgress,
          join: b in ^Access.books(access),
          on: rp.book_id == b.id,
          where: rp.user_id == ^user_id and is_nil(b.deleted_at),
          select: {rp.current_page, b.page_count}
        )
        |> Repo.all()

      in_progress =
        Enum.count(progress_rows, fn {cur, pages} ->
          pages && pages > 1 && cur > 0 && cur < pages - 1
        end)

      completed =
        Enum.count(progress_rows, fn {cur, pages} ->
          pages && pages > 0 && cur >= pages - 1
        end)

      unread = total - in_progress - completed

      %{total: total, unread: unread, in_progress: in_progress, completed: completed}
    end
  end

  def stats_top_series(access, limit \\ 10) do
    from(s in Series,
      join: b in ^Access.books(access),
      on: b.series_id == s.id and is_nil(b.deleted_at),
      where: is_nil(s.deleted_at),
      group_by: [s.id, s.name],
      order_by: [desc: count(b.id)],
      limit: ^limit,
      select: {s.name, count(b.id)}
    )
    |> Repo.all()
  end

  def stats_series_by_format(access) do
    from(s in Access.series(access),
      where: is_nil(s.deleted_at) and not is_nil(s.format),
      group_by: s.format,
      select: {s.format, count(s.id)}
    )
    |> Repo.all()
  end

  def stats_file_size_by_publisher(access) do
    from(bf in BookFile,
      join: b in ^Access.books(access),
      on: bf.book_id == b.id and is_nil(b.deleted_at),
      join: bp in "book_publishers",
      on: bp.book_id == b.id,
      join: p in Publisher,
      on: p.id == bp.publisher_id and is_nil(p.canonical_publisher_id),
      where: is_nil(bf.deleted_at) and p.hidden == false,
      group_by: [p.id, p.name],
      order_by: [desc: sum(bf.file_size)],
      select: {p.id, p.name, sum(bf.file_size)}
    )
    |> Repo.all()
  end

  def stats_books_by_file_format(access) do
    from(bf in BookFile,
      join: b in ^Access.books(access),
      on: bf.book_id == b.id,
      where: is_nil(bf.deleted_at) and is_nil(b.deleted_at),
      group_by: bf.format,
      order_by: [desc: count(bf.book_id)],
      select: {bf.format, count(bf.book_id)}
    )
    |> Repo.all()
  end

  def stats_books_by_language(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at) and not is_nil(b.language),
      group_by: fragment("lower(?)", b.language),
      order_by: [desc: count(b.id)],
      select: {fragment("lower(?)", b.language), count(b.id)}
    )
    |> Repo.all()
  end

  def stats_books_by_age_rating(access) do
    from(b in Access.books(access),
      where: is_nil(b.deleted_at) and not is_nil(b.age_rating),
      group_by: b.age_rating,
      order_by: [desc: count(b.id)],
      select: {b.age_rating, count(b.id)}
    )
    |> Repo.all()
  end

  def stats_top_genres(access, limit \\ 20) do
    from(g in Stashix.Library.BookGenre,
      join: b in ^Access.books(access),
      on: g.book_id == b.id and is_nil(b.deleted_at),
      group_by: g.name,
      order_by: [desc: count(g.id)],
      limit: ^limit,
      select: {g.name, count(g.id)}
    )
    |> Repo.all()
  end

  def stats_top_creators(access, limit \\ 20) do
    from(c in Stashix.Library.Creator,
      join: bc in Stashix.Library.BookCredit,
      on: bc.creator_id == c.id,
      join: b in ^Access.books(access),
      on: bc.book_id == b.id and is_nil(b.deleted_at),
      group_by: c.name,
      order_by: [desc: count(bc.id)],
      limit: ^limit,
      select: {c.name, count(bc.id)}
    )
    |> Repo.all()
  end

  def stats_credits_by_role(access) do
    from(bc in Stashix.Library.BookCredit,
      join: b in ^Access.books(access),
      on: bc.book_id == b.id and is_nil(b.deleted_at),
      group_by: bc.role,
      order_by: [desc: count(bc.id)],
      select: {bc.role, count(bc.id)}
    )
    |> Repo.all()
  end

  def stats_top_characters(access, limit \\ 20) do
    from(ch in Stashix.Library.BookCharacter,
      join: b in ^Access.books(access),
      on: ch.book_id == b.id and is_nil(b.deleted_at),
      group_by: ch.name,
      order_by: [desc: count(ch.id)],
      limit: ^limit,
      select: {ch.name, count(ch.id)}
    )
    |> Repo.all()
  end

  def stats_top_publishers_by_count(access, limit \\ 20) do
    from(p in Publisher,
      join: bp in "book_publishers",
      on: bp.publisher_id == p.id,
      join: b in ^Access.books(access),
      on: bp.book_id == b.id and is_nil(b.deleted_at),
      where: is_nil(p.canonical_publisher_id) and p.hidden == false,
      group_by: [p.id, p.name],
      order_by: [desc: count(b.id)],
      limit: ^limit,
      select: {p.id, p.name, count(b.id)}
    )
    |> Repo.all()
  end

  def stats_total_pages(access) do
    from(bf in BookFile,
      join: b in ^Access.books(access),
      on: bf.book_id == b.id and is_nil(b.deleted_at),
      where: is_nil(bf.deleted_at),
      select: sum(bf.page_count)
    )
    |> Repo.one()
  end

  def stats_total_file_size(access) do
    from(bf in BookFile,
      join: b in ^Access.books(access),
      on: bf.book_id == b.id and is_nil(b.deleted_at),
      where: is_nil(bf.deleted_at),
      select: sum(bf.file_size)
    )
    |> Repo.one()
  end

  def stats_metadata_coverage(access) do
    total =
      from(b in Access.books(access), where: is_nil(b.deleted_at), select: count(b.id))
      |> Repo.one()

    with_summary =
      from(b in Access.books(access),
        where: is_nil(b.deleted_at) and not is_nil(b.summary) and b.summary != "",
        select: count(b.id)
      )
      |> Repo.one()

    with_genres =
      from(b in Access.books(access),
        join: g in Stashix.Library.BookGenre,
        on: g.book_id == b.id,
        where: is_nil(b.deleted_at),
        select: count(b.id, :distinct)
      )
      |> Repo.one()

    with_credits =
      from(b in Access.books(access),
        join: bc in Stashix.Library.BookCredit,
        on: bc.book_id == b.id,
        where: is_nil(b.deleted_at),
        select: count(b.id, :distinct)
      )
      |> Repo.one()

    with_external_ids =
      from(b in Access.books(access),
        join: ei in Stashix.Library.BookExternalId,
        on: ei.book_id == b.id,
        where: is_nil(b.deleted_at),
        select: count(b.id, :distinct)
      )
      |> Repo.one()

    %{
      total: total,
      with_summary: with_summary,
      with_genres: with_genres,
      with_credits: with_credits,
      with_external_ids: with_external_ids
    }
  end
end
