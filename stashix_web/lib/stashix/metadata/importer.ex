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
  """
  def replace_book_metadata(book, metadata) when is_map(metadata) do
    Repo.transaction(fn ->
      book_id = book.id
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      replace_simple(BookGenre, book_id, metadata[:genres] || [], now, fn name ->
        %{name: name}
      end)

      replace_simple(BookTag, book_id, metadata[:tags] || [], now, fn name ->
        %{name: name}
      end)

      replace_simple(BookStoryArc, book_id, metadata[:arcs] || [], now, fn arc ->
        %{name: arc.name, arc_number: arc[:arc_number], external_id: arc[:external_id]}
      end)

      replace_simple(BookStory, book_id, metadata[:stories] || [], now, fn s ->
        %{name: s.name, external_id: s[:external_id]}
      end)

      replace_simple(BookCharacter, book_id, metadata[:characters] || [], now, fn c ->
        %{name: c.name, external_id: c[:external_id]}
      end)

      replace_simple(BookTeam, book_id, metadata[:teams] || [], now, fn t ->
        %{name: t.name, external_id: t[:external_id]}
      end)

      replace_simple(BookUniverse, book_id, metadata[:universes] || [], now, fn u ->
        %{name: u.name, designation: u[:designation], external_id: u[:external_id]}
      end)

      replace_simple(BookLocation, book_id, metadata[:locations] || [], now, fn l ->
        %{name: l.name, external_id: l[:external_id]}
      end)

      replace_simple(BookReprint, book_id, metadata[:reprints] || [], now, fn r ->
        %{name: r.name, external_id: r[:external_id]}
      end)

      replace_simple(BookUrl, book_id, metadata[:urls] || [], now, fn u ->
        %{url: u.url, is_primary: u[:is_primary] || false}
      end)

      replace_simple(BookPrice, book_id, metadata[:prices] || [], now, fn p ->
        %{amount: p.amount, country: p.country}
      end)

      replace_external_ids(book_id, metadata[:external_ids] || [], now)

      replace_credits(book_id, metadata[:credits] || [], now)

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
        Enum.map(ids, fn id ->
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

  # MetronInfo "Cover" → stored as "Cover Artist"
  defp normalize_role("Cover"), do: :"Cover Artist"
  defp normalize_role(role), do: String.to_existing_atom(role)
end
