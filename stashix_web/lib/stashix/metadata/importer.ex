defmodule Stashix.Metadata.Importer do
  import Ecto.Query
  alias Stashix.Repo

  alias Stashix.Library.{
    BookExternalId,
    BookGenre,
    BookTag,
    BookStoryArc,
    BookStory,
    BookCharacter,
    BookTeam,
    BookUniverse,
    BookLocation,
    BookReprint,
    BookUrl,
    BookPrice,
    BookCredit,
    Creator
  }

  @doc """
  Replaces all structured metadata for a book from a parsed MetronInfo/ComicInfo map.
  Runs in a transaction; safe to call on create or re-scan.

  Options:
    * `:only_present` - when true, child tables whose key is absent from
      `metadata` are left untouched instead of being cleared.
    * `:external_ids` - `:replace` (default) or `:merge`. Merge upserts the given
      ids per source and keeps ids from other sources, used when applying data
      fetched from a metadata source.
  """
  def replace_book_metadata(book, metadata, opts \\ []) when is_map(metadata) do
    Repo.transaction(fn ->
      book_id = book.id
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      only_present = Keyword.get(opts, :only_present, false)
      touch? = fn key -> not only_present or Map.has_key?(metadata, key) end

      if touch?.(:genres),
        do:
          replace_simple(BookGenre, book_id, metadata[:genres] || [], now, fn name ->
            %{name: name}
          end)

      if touch?.(:tags),
        do:
          replace_simple(BookTag, book_id, metadata[:tags] || [], now, fn name ->
            %{name: name}
          end)

      if touch?.(:arcs),
        do:
          replace_simple(BookStoryArc, book_id, metadata[:arcs] || [], now, fn arc ->
            %{name: arc.name, arc_number: arc[:arc_number], external_id: arc[:external_id]}
          end)

      if touch?.(:stories),
        do:
          replace_simple(BookStory, book_id, metadata[:stories] || [], now, fn s ->
            %{name: s.name, external_id: s[:external_id]}
          end)

      if touch?.(:characters),
        do:
          replace_simple(BookCharacter, book_id, metadata[:characters] || [], now, fn c ->
            %{name: c.name, external_id: c[:external_id]}
          end)

      if touch?.(:teams),
        do:
          replace_simple(BookTeam, book_id, metadata[:teams] || [], now, fn t ->
            %{name: t.name, external_id: t[:external_id]}
          end)

      if touch?.(:universes),
        do:
          replace_simple(BookUniverse, book_id, metadata[:universes] || [], now, fn u ->
            %{name: u.name, designation: u[:designation], external_id: u[:external_id]}
          end)

      if touch?.(:locations),
        do:
          replace_simple(BookLocation, book_id, metadata[:locations] || [], now, fn l ->
            %{name: l.name, external_id: l[:external_id]}
          end)

      if touch?.(:reprints),
        do:
          replace_simple(BookReprint, book_id, metadata[:reprints] || [], now, fn r ->
            %{name: r.name, external_id: r[:external_id]}
          end)

      if touch?.(:urls),
        do:
          replace_simple(BookUrl, book_id, metadata[:urls] || [], now, fn u ->
            %{url: u.url, is_primary: u[:is_primary] || false}
          end)

      if touch?.(:prices),
        do:
          replace_simple(BookPrice, book_id, metadata[:prices] || [], now, fn p ->
            %{amount: p.amount, country: p.country}
          end)

      if touch?.(:external_ids) do
        case Keyword.get(opts, :external_ids, :replace) do
          :merge -> upsert_external_ids(BookExternalId, :book_id, book_id, metadata[:external_ids] || [])
          :replace -> replace_external_ids(book_id, metadata[:external_ids] || [], now)
        end
      end

      if touch?.(:credits), do: replace_credits(book_id, metadata[:credits] || [], now)

      :ok
    end)
  end

  defp replace_simple(schema, book_id, items, now, row_fn) do
    Repo.delete_all(from r in schema, where: r.book_id == ^book_id)

    if items != [] do
      rows =
        items
        |> Enum.map(fn item ->
          row_fn.(item)
          |> Map.merge(%{
            id: Ecto.UUID.generate(),
            book_id: book_id,
            inserted_at: now,
            updated_at: now
          })
        end)

      Repo.insert_all(schema, rows, on_conflict: :nothing)
    end
  end

  defp replace_external_ids(book_id, ids, now) do
    Repo.delete_all(from e in BookExternalId, where: e.book_id == ^book_id)

    if ids != [] do
      rows =
        ids
        |> Enum.map(&Map.put(&1, :source, normalize_source(&1.source, BookExternalId)))
        |> Enum.uniq_by(& &1.source)
        |> Enum.map(fn id ->
          %{
            id: Ecto.UUID.generate(),
            book_id: book_id,
            source: id.source,
            source_id: id.source_id,
            is_primary: id[:is_primary] || false,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(BookExternalId, rows, on_conflict: :nothing)
    end
  end

  defp replace_credits(book_id, credits, now) do
    Repo.delete_all(from c in BookCredit, where: c.book_id == ^book_id)

    for %{creator: name, roles: roles} <- credits, roles != [] do
      creator = find_or_create_creator(name)

      rows =
        roles
        |> Enum.map(&normalize_role/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn role ->
          %{
            id: Ecto.UUID.generate(),
            book_id: book_id,
            creator_id: creator.id,
            role: role,
            inserted_at: now,
            updated_at: now
          }
        end)

      if rows != [] do
        Repo.insert_all(BookCredit, rows, on_conflict: :nothing)
      end
    end
  end

  defp find_or_create_creator(name) do
    case Repo.get_by(Creator, name: name) do
      nil ->
        case Repo.insert(%Creator{name: name}) do
          {:ok, c} -> c
          {:error, _} -> Repo.get_by!(Creator, name: name)
        end

      c ->
        c
    end
  end

  @doc """
  Adds links to a book, keeping the ones it already has so a book can point at
  several metadata sources. Duplicate urls are skipped, and a new link is only
  primary when the book has no primary link yet.
  """
  def merge_urls(book_id, urls) do
    existing = Repo.all(from u in BookUrl, where: u.book_id == ^book_id, select: {u.url, u.is_primary})
    known = MapSet.new(existing, fn {url, _} -> url end)
    has_primary = Enum.any?(existing, fn {_, primary} -> primary end)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      urls
      |> Enum.map(&Map.update!(&1, :url, fn url -> String.trim(url) end))
      |> Enum.reject(&(&1.url == "" or MapSet.member?(known, &1.url)))
      |> Enum.uniq_by(& &1.url)
      |> Enum.map(fn u ->
        %{
          id: Ecto.UUID.generate(),
          book_id: book_id,
          url: u.url,
          is_primary: not has_primary and (u[:is_primary] || false),
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [], do: Repo.insert_all(BookUrl, rows)
    :ok
  end

  @doc """
  Upserts external ids (one per source) for a book or series, leaving ids from
  other sources untouched. `schema` is `BookExternalId` or `SeriesExternalId`.
  """
  def upsert_external_ids(schema, owner_field, owner_id, ids) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    ids
    |> Enum.map(&Map.put(&1, :source, normalize_source(&1.source, schema)))
    |> Enum.reject(&(&1.source == :Unknown))
    |> Enum.uniq_by(& &1.source)
    |> Enum.each(fn id ->
      row = %{
        id: Ecto.UUID.generate(),
        source: id.source,
        source_id: to_string(id.source_id),
        is_primary: id[:is_primary] || false,
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(schema, [Map.put(row, owner_field, owner_id)],
        on_conflict: {:replace, [:source_id, :is_primary, :updated_at]},
        conflict_target: [owner_field, :source]
      )
    end)

    :ok
  end

  defp normalize_source(source, schema) when is_atom(source) and not is_nil(source),
    do: normalize_source(Atom.to_string(source), schema)

  defp normalize_source(source, schema) when is_binary(source) do
    Ecto.Enum.values(schema, :source)
    |> Enum.find(:Unknown, &(Atom.to_string(&1) == source))
  end

  defp normalize_source(_, _), do: :Unknown

  @role_lookup BookCredit
               |> Ecto.Enum.values(:role)
               |> Map.new(&{&1 |> Atom.to_string() |> String.downcase(), &1})

  # MetronInfo "Cover" → stored as "Cover Artist"; unknown roles become Other
  # instead of raising, so one odd credit can't abort the import.
  def normalize_role(role) when is_atom(role) and not is_nil(role), do: normalize_role(Atom.to_string(role))
  def normalize_role("Cover"), do: :"Cover Artist"

  def normalize_role(role) when is_binary(role) do
    Map.get(@role_lookup, role |> String.trim() |> String.downcase(), :Other)
  end

  def normalize_role(_), do: nil
end
