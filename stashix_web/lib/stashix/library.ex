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
    sort = Keyword.get(opts, :sort, :inserted_at)
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
        :title -> order_by(query, [b], asc: b.title)
        :issue_number -> order_by(query, [b], asc: b.issue_number)
        _ -> order_by(query, [b], desc: b.inserted_at)
      end

    Repo.all(query)
  end

  def get_book!(id), do: Repo.get!(Book, id)

  def get_book_with_series(id) do
    Repo.get!(Book, id) |> Repo.preload([:series, :cover, :publisher])
  end

  def list_series(library_id) do
    from(s in Series,
      where: s.library_id == ^library_id,
      preload: [:publisher]
    )
    |> Repo.all()
  end

  def get_series!(id), do: Repo.get!(Series, id)

  def get_series_with_books(id) do
    Repo.get!(Series, id) |> Repo.preload(books: from(b in Book, where: is_nil(b.deleted_at), order_by: [asc: b.issue_number]))
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

  def create_or_find_series(attrs) do
    case Repo.get_by(Series, library_id: attrs.library_id, name: attrs.name) do
      nil ->
        %Series{}
        |> Series.changeset(attrs)
        |> Repo.insert()

      series ->
        {:ok, series}
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
    Repo.aggregate(from(s in Series, where: s.library_id == ^library_id), :count, :id)
  end

  def recent_books(library_id, limit \\ 10) do
    from(b in Book,
      where: b.library_id == ^library_id and is_nil(b.deleted_at),
      order_by: [desc: b.inserted_at],
      limit: ^limit,
      preload: [:cover]
    )
    |> Repo.all()
  end
end
