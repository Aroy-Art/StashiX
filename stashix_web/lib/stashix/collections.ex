# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Collections do
  @moduledoc """
  Users' collections of books and whole series (docs/collections-plan.md).

  Rules:

    * Only the owner changes a collection or its entries. Others see it when
      it is `shared` and holds something they may read.
    * What a viewer sees is the entries expanded — a series stands for its
      books, in issue order, now and as issues are added — without
      duplicates (a book listed alone and in a listed series shows once, at
      its first place) and limited by the viewer's `Access`. Counts are the
      viewer's counts.
    * Entries keep the owner's order (`position`, with gaps of
      #{1024}); viewers may sort by title, year or date added instead.
  """

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Accounts.User
  alias Stashix.Library.{Access, Book, Collection, CollectionEntry, Series}

  @gap 1024

  ## Collections

  @doc """
  The collections `user` sees: their own (even empty) and others' shared
  ones that hold something they may read. Each as `%{collection, own?,
  count, cover_ids}`, `cover_ids` being the first books' ids (up to 4). Own
  first, then by name.
  """
  def list_for(%User{id: user_id}, %Access{} = access) do
    collections =
      from(c in Collection, where: c.user_id == ^user_id or c.shared == true, preload: :user)
      |> Repo.all()

    expanded = collections |> Enum.map(& &1.id) |> expanded_ids(access)

    collections
    |> Enum.map(fn c ->
      ids = Map.get(expanded, c.id, [])
      %{collection: c, own?: c.user_id == user_id, count: length(ids), cover_ids: cover_ids(c, ids)}
    end)
    |> Enum.filter(&(&1.own? or &1.count > 0))
    |> Enum.sort_by(&{not &1.own?, String.downcase(&1.collection.name)})
  end

  @doc "The collections `user` sees (see `list_for/2`) whose name contains `query`, ignoring case."
  def search(%User{} = user, %Access{} = access, query) when is_binary(query) do
    case query |> String.trim() |> String.downcase() do
      "" -> []
      q -> user |> list_for(access) |> Enum.filter(&String.contains?(String.downcase(&1.collection.name), q))
    end
  end

  # The picked cover first, when the viewer may see that book; then the first books.
  defp cover_ids(%Collection{cover_book_id: cover}, ids) do
    if cover && cover in ids, do: [cover | List.delete(ids, cover)] |> Enum.take(4), else: Enum.take(ids, 4)
  end

  @doc """
  The book whose cover stands for the collection, for a viewer: the picked
  one if they may see it, else the first book. nil when empty.
  """
  def cover_book_id(%Access{} = access, %Collection{} = c) do
    ids = [c.id] |> expanded_ids(access) |> Map.get(c.id, [])
    ids |> then(&cover_ids(c, &1)) |> List.first()
  end

  @doc """
  Picks the collection's cover: a book (`{:book, id}`), a series (its first
  book the owner may read: `{:series, id}`), or nil to go back to the first
  books.
  """
  def set_cover(%User{} = user, %Access{} = access, %Collection{} = c, item) do
    with :ok <- check_owner(c, user),
         {:ok, book_id} <- cover_for(access, item) do
      c |> Ecto.Changeset.change(cover_book_id: book_id) |> Repo.update()
    end
  end

  defp cover_for(_access, nil), do: {:ok, nil}

  defp cover_for(access, {:book, id}),
    do: if(readable?(access, :book, id), do: {:ok, id}, else: {:error, :not_found})

  defp cover_for(access, {:series, id}) do
    from(b in Access.books(access),
      where: b.series_id == ^id and is_nil(b.deleted_at),
      order_by: [asc_nulls_last: b.issue_number, asc: b.title],
      limit: 1,
      select: b.id
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      book_id -> {:ok, book_id}
    end
  end

  @doc "`user`'s own collections, by name (for pickers)."
  def own(%User{id: user_id}) do
    from(c in Collection, where: c.user_id == ^user_id, order_by: fragment("lower(?)", c.name)) |> Repo.all()
  end

  @doc """
  A collection `user` may see (theirs, or shared with something they may
  read): `{:ok, collection}` or `{:error, :not_found}`.
  """
  def get(%User{id: user_id}, %Access{} = access, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Collection{} = c <- Repo.get(Collection, id) |> Repo.preload(:user),
         true <- c.user_id == user_id or (c.shared and expanded_ids([c.id], access) |> Map.has_key?(c.id)) do
      {:ok, c}
    else
      _ -> {:error, :not_found}
    end
  end

  def owner?(%Collection{user_id: owner}, %User{id: user_id}), do: owner == user_id

  def create(%User{id: user_id}, attrs) do
    %Collection{user_id: user_id} |> Collection.changeset(attrs) |> Repo.insert()
  end

  def update(%User{} = user, %Collection{} = c, attrs) do
    with :ok <- check_owner(c, user), do: c |> Collection.changeset(attrs) |> Repo.update()
  end

  def delete(%User{} = user, %Collection{} = c) do
    with :ok <- check_owner(c, user), do: Repo.delete(c)
  end

  defp check_owner(c, user), do: if(owner?(c, user), do: :ok, else: {:error, :forbidden})

  ## Entries

  @doc """
  Adds a book (`{:book, id}`) or a whole series (`{:series, id}`) at the
  end. The owner must be able to read it. `{:ok, entry}`, or `{:ok, :exists}`
  when it is already there.
  """
  def add(%User{} = user, %Access{} = access, %Collection{} = c, {kind, id}) when kind in [:book, :series] do
    with :ok <- check_owner(c, user),
         true <- readable?(access, kind, id) || {:error, :not_found} do
      key = if kind == :book, do: :book_id, else: :series_id

      if Repo.exists?(from e in CollectionEntry, where: e.collection_id == ^c.id and field(e, ^key) == ^id) do
        {:ok, :exists}
      else
        %CollectionEntry{collection_id: c.id, position: next_position(c.id)}
        |> Map.put(key, id)
        |> Repo.insert()
        |> tap(fn _ -> touch(c) end)
      end
    end
  end

  @doc "Removes a book or series entry (by what it holds). `:ok` also when it wasn't there."
  def remove(%User{} = user, %Collection{} = c, {kind, id}) when kind in [:book, :series] do
    with :ok <- check_owner(c, user) do
      key = if kind == :book, do: :book_id, else: :series_id
      from(e in CollectionEntry, where: e.collection_id == ^c.id and field(e, ^key) == ^id) |> Repo.delete_all()
      touch(c)
      :ok
    end
  end

  @doc """
  Takes a book out of a collection however it is in it: its own entry goes,
  and if it is there through a series entry, that series entry becomes the
  series' other books (those the owner may read), in its place. For clients
  that only know books, such as a Kobo shelf.
  """
  def remove_book(%User{} = user, %Access{} = access, %Collection{} = c, book_id) do
    with :ok <- check_owner(c, user) do
      series_id = Repo.one(from b in Book, where: b.id == ^book_id, select: b.series_id)

      Repo.transaction(fn ->
        from(e in CollectionEntry, where: e.collection_id == ^c.id and e.book_id == ^book_id) |> Repo.delete_all()

        series_entry =
          series_id &&
            Repo.one(from e in CollectionEntry, where: e.collection_id == ^c.id and e.series_id == ^series_id)

        if series_entry, do: spread_series(access, c, series_entry, book_id)
        touch(c)
      end)

      :ok
    end
  end

  # The series entry becomes one entry per remaining book, where it was.
  defp spread_series(access, c, series_entry, without_book_id) do
    held = from(e in CollectionEntry, where: e.collection_id == ^c.id and not is_nil(e.book_id), select: e.book_id)

    book_ids =
      from(b in Access.books(access),
        where:
          b.series_id == ^series_entry.series_id and is_nil(b.deleted_at) and b.id != ^without_book_id and
            b.id not in subquery(held),
        order_by: [asc_nulls_last: b.issue_number, asc: b.title],
        select: b.id
      )
      |> Repo.all()

    entries =
      from(e in CollectionEntry, where: e.collection_id == ^c.id, order_by: [e.position, e.inserted_at]) |> Repo.all()

    Repo.delete!(series_entry)

    new =
      for id <- book_ids, do: Repo.insert!(%CollectionEntry{collection_id: c.id, book_id: id, position: 0})

    entries
    |> Enum.flat_map(fn e -> if e.id == series_entry.id, do: new, else: [e] end)
    |> renumber()
  end

  @doc "Removes an entry by its id."
  def remove_entry(%User{} = user, %Collection{} = c, entry_id) do
    with :ok <- check_owner(c, user),
         {:ok, entry_id} <- Ecto.UUID.cast(entry_id) do
      from(e in CollectionEntry, where: e.collection_id == ^c.id and e.id == ^entry_id) |> Repo.delete_all()
      touch(c)
      :ok
    end
  end

  @doc """
  Moves an entry to `index` (0-based) among the collection's entries.
  Takes the middle of its new neighbours' positions; renumbers every entry
  when there is no room left between them.
  """
  def move(%User{} = user, %Collection{} = c, entry_id, index) when is_integer(index) do
    with :ok <- check_owner(c, user) do
      entries =
        from(e in CollectionEntry, where: e.collection_id == ^c.id, order_by: [e.position, e.inserted_at]) |> Repo.all()

      case Enum.split_with(entries, &(&1.id == entry_id)) do
        {[entry], others} ->
          index = index |> max(0) |> min(length(others))
          before = if index > 0, do: Enum.at(others, index - 1).position
          after_ = Enum.at(others, index) && Enum.at(others, index).position

          position =
            case {before, after_} do
              {nil, nil} -> @gap
              {nil, a} -> a - @gap
              {b, nil} -> b + @gap
              {b, a} when a - b > 1 -> div(a + b, 2)
              _ -> nil
            end

          Repo.transaction(fn ->
            if position do
              set_position(entry.id, position)
            else
              others |> List.insert_at(index, entry) |> renumber()
            end

            touch(c)
          end)

          :ok

        _ ->
          {:error, :not_found}
      end
    end
  end

  defp renumber(entries) do
    entries |> Enum.with_index(1) |> Enum.each(fn {e, i} -> set_position(e.id, i * @gap) end)
  end

  defp set_position(id, position),
    do: from(e in CollectionEntry, where: e.id == ^id) |> Repo.update_all(set: [position: position])

  defp next_position(collection_id) do
    (Repo.one(from e in CollectionEntry, where: e.collection_id == ^collection_id, select: max(e.position)) || 0) + @gap
  end

  # Entries changed: the collection counts as changed (OPDS and Kobo go by it).
  defp touch(c),
    do:
      from(x in Collection, where: x.id == ^c.id)
      |> Repo.update_all(set: [updated_at: DateTime.utc_now() |> DateTime.truncate(:second)])

  defp readable?(access, :book, id),
    do: Repo.exists?(from b in Access.books(access), where: b.id == ^id and is_nil(b.deleted_at))

  defp readable?(access, :series, id),
    do: Repo.exists?(from s in Access.series(access), where: s.id == ^id and is_nil(s.deleted_at))

  @doc """
  The collection's entries the viewer can see, in its order, with the book
  or series loaded: a book entry they may read, a series entry with at least
  one book they may read.
  """
  def entries(%Access{} = access, %Collection{id: id}) do
    books = from(b in Access.books(access), where: is_nil(b.deleted_at), select: b.id)
    series = from(s in Access.series(access), where: is_nil(s.deleted_at), select: s.id)

    from(e in CollectionEntry,
      where: e.collection_id == ^id,
      where: e.book_id in subquery(books) or e.series_id in subquery(series),
      order_by: [e.position, e.inserted_at],
      preload: [book: [:cover, :series], series: []]
    )
    |> Repo.all()
    |> put_series_counts(access)
  end

  # A series card shows how many of its books the viewer may read.
  defp put_series_counts(entries, access) do
    series_ids = for %{series_id: id} <- entries, id, do: id

    counts =
      from(b in Access.books(access),
        where: b.series_id in ^series_ids and is_nil(b.deleted_at),
        group_by: b.series_id,
        select: {b.series_id, count(b.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(entries, fn
      %{series: %Series{} = s} = e -> %{e | series: %{s | issue_count: Map.get(counts, s.id, 0)}}
      e -> e
    end)
  end

  @doc """
  Which of `user`'s collections hold a book or series: `%{collection_id =>
  :direct | :series}` (`:series`: the book is there through its series).
  """
  def containing(%User{id: user_id}, {:series, series_id}) do
    from(e in CollectionEntry,
      join: c in Collection,
      on: c.id == e.collection_id,
      where: c.user_id == ^user_id and e.series_id == ^series_id,
      select: {c.id, :direct}
    )
    |> Repo.all()
    |> Map.new()
  end

  def containing(%User{id: user_id}, {:book, book_id}) do
    series_id = Repo.one(from b in Book, where: b.id == ^book_id, select: b.series_id)

    from(e in CollectionEntry,
      join: c in Collection,
      on: c.id == e.collection_id,
      where: c.user_id == ^user_id,
      where: ^holds_book(book_id, series_id),
      select: {c.id, e.book_id}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {cid, book}, acc ->
      Map.update(acc, cid, if(book, do: :direct, else: :series), &if(book, do: :direct, else: &1))
    end)
  end

  @doc """
  The collections (own and shared with them) a viewer sees that hold a
  book, directly or through its series — for the book page.
  """
  def holding_book(%User{} = user, %Access{} = access, book_id) do
    series_id = Repo.one(from b in Book, where: b.id == ^book_id, select: b.series_id)

    ids =
      from(e in CollectionEntry,
        join: c in Collection,
        on: c.id == e.collection_id,
        where: c.user_id == ^user.id or c.shared == true,
        where: ^holds_book(book_id, series_id),
        distinct: true,
        select: c.id
      )
      |> Repo.all()

    list_for(user, access) |> Enum.filter(&(&1.collection.id in ids)) |> Enum.map(& &1.collection)
  end

  # An entry for the book itself, or for its series.
  defp holds_book(book_id, nil), do: dynamic([e], e.book_id == ^book_id)
  defp holds_book(book_id, series_id), do: dynamic([e], e.book_id == ^book_id or e.series_id == ^series_id)

  ## Books

  @doc """
  The viewer's books of a collection, sorted (`"position"`, `"title"`,
  `"year"` or `"added"`) and paged (`:limit`, `:offset`):
  `{books, total}`. Books come with `:cover` and `:series`.
  """
  def books(%Access{} = access, %Collection{id: id}, sort \\ "position", opts \\ []) do
    rows = id |> List.wrap() |> expanded_rows(access) |> Map.get(id, [])

    sorted =
      case sort do
        "title" -> Enum.sort_by(rows, &String.downcase(&1.title || ""))
        "year" -> Enum.sort_by(rows, &{is_nil(&1.year), &1.year, String.downcase(&1.title || "")})
        "added" -> Enum.sort_by(rows, & &1.added, {:desc, DateTime})
        _ -> rows
      end

    limit = Keyword.get(opts, :limit, length(sorted))
    page_ids = sorted |> Enum.drop(Keyword.get(opts, :offset, 0)) |> Enum.take(limit) |> Enum.map(& &1.book_id)

    loaded =
      from(b in Book, where: b.id in ^page_ids, preload: [:cover, :series]) |> Repo.all() |> Map.new(&{&1.id, &1})

    {Enum.map(page_ids, &loaded[&1]), length(sorted)}
  end

  @doc "Ids of the viewer's books in each collection, in collection order: `%{collection_id => [book_id]}`."
  def expanded_ids(collection_ids, %Access{} = access) do
    collection_ids |> expanded_rows(access) |> Map.new(fn {cid, rows} -> {cid, Enum.map(rows, & &1.book_id)} end)
  end

  # Every visible book of the collections, as rows with what sorting needs,
  # in collection order and without duplicates: one query for all of them.
  defp expanded_rows([], _access), do: %{}

  defp expanded_rows(collection_ids, access) do
    books =
      from(e in CollectionEntry,
        join: b in ^Access.books(access),
        on: b.id == e.book_id,
        where: e.collection_id in ^collection_ids and is_nil(b.deleted_at),
        select: %{
          collection_id: e.collection_id,
          book_id: b.id,
          position: e.position,
          issue_number: b.issue_number,
          title: b.title,
          year: b.year,
          added: e.inserted_at
        }
      )

    series_books =
      from(e in CollectionEntry,
        join: s in Series,
        on: s.id == e.series_id and is_nil(s.deleted_at),
        join: b in ^Access.books(access),
        on: b.series_id == e.series_id,
        where: e.collection_id in ^collection_ids and is_nil(b.deleted_at),
        select: %{
          collection_id: e.collection_id,
          book_id: b.id,
          position: e.position,
          issue_number: b.issue_number,
          title: b.title,
          year: b.year,
          added: e.inserted_at
        }
      )

    books
    |> union_all(^series_books)
    |> Repo.all()
    |> Enum.group_by(& &1.collection_id)
    |> Map.new(fn {cid, rows} ->
      rows =
        rows
        |> Enum.sort_by(
          &{&1.position, is_nil(&1.issue_number), &1.issue_number && Decimal.to_float(&1.issue_number),
           String.downcase(&1.title || "")}
        )
        |> Enum.uniq_by(& &1.book_id)

      {cid, rows}
    end)
  end
end
