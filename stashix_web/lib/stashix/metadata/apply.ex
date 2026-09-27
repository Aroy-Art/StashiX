defmodule Stashix.Metadata.Apply do
  @moduledoc """
  Persists metadata fetched from a source onto a book or series.

  `overwrite_mode` (from `Stashix.Settings.metadata/0`):
    * `"replace"` - every field the source provides replaces the local value
    * `"fill"`    - only empty local fields are filled in
  External ids are always merged, never replaced.
  """
  alias Stashix.Repo
  alias Stashix.Library
  alias Stashix.Library.{Book, Series, Imprint, BookExternalId, SeriesExternalId}
  alias Stashix.Metadata.Importer

  @book_fields ~w(title volume year language summary age_rating collection_title alternative_number
                  isbn upc cover_date store_date notes community_rating community_rating_count)a

  @child_keys ~w(genres tags arcs stories characters teams universes locations reprints urls prices credits)a

  @child_assocs %{
    genres: :genres,
    tags: :tags,
    arcs: :story_arcs,
    stories: :stories,
    characters: :characters,
    teams: :teams,
    universes: :universes,
    locations: :locations,
    reprints: :reprints,
    urls: :urls,
    prices: :prices,
    credits: :credits
  }

  @series_fields ~w(name sort_name volume format start_year end_year issue_count summary language ongoing)a

  @doc "Applies issue-level metadata (the `fetch_issue/2` map) to a book."
  def apply_book(%Book{} = book, source_mod, metadata, settings) do
    mode = settings["overwrite_mode"] || "replace"
    book = Repo.preload(book, [:series | Map.values(@child_assocs)])

    attrs =
      @book_fields
      |> Enum.reduce(%{}, fn field, acc ->
        maybe_set(acc, field, Map.get(metadata, field), Map.get(book, field), mode)
      end)
      # Never clobber a known issue number / real page count from the file.
      |> maybe_set(:issue_number, metadata[:issue_number], book.issue_number, "fill")
      |> maybe_set(:page_count, metadata[:page_count], zero_to_nil(book.page_count), "fill")
      |> maybe_put_imprint(metadata)
      |> Map.merge(%{
        metadata_matched_at: NaiveDateTime.utc_now(:second),
        metadata_source: source_mod.key()
      })

    children =
      @child_keys
      |> Enum.filter(fn key ->
        Map.has_key?(metadata, key) and
          (mode == "replace" or Map.get(book, @child_assocs[key]) == [])
      end)
      |> then(&Map.take(metadata, &1))

    Repo.transaction(fn ->
      with {:ok, updated} <- Library.update_book(book, attrs),
           {:ok, _} <- Importer.replace_book_metadata(updated, children, only_present: true) do
        Importer.upsert_external_ids(BookExternalId, :book_id, book.id, metadata[:external_ids] || [])
        link_publisher(updated, book.series, metadata[:publisher])

        if book.series do
          apply_series_from_issue(book.series, metadata)
        end

        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Issue payloads carry some series info; only fill gaps, never rename folders' series.
  defp apply_series_from_issue(%Series{metadata_locked: true}, _), do: :ok

  defp apply_series_from_issue(%Series{} = series, metadata) do
    attrs =
      %{}
      |> maybe_set(:sort_name, metadata[:series_sort_name], series.sort_name, "fill")
      |> maybe_set(:format, metadata[:series_format], series.format, "fill")
      |> maybe_set(:start_year, metadata[:series_start_year], series.start_year, "fill")
      |> maybe_set(:volume, metadata[:volume], series.volume, "fill")

    if attrs != %{}, do: Library.update_series(series, attrs)

    Importer.upsert_external_ids(
      SeriesExternalId,
      :series_id,
      series.id,
      metadata[:series_external_ids] || []
    )
  end

  @doc "Applies series-level metadata (the `fetch_series/2` map) to a series."
  def apply_series(%Series{} = series, source_mod, metadata, settings) do
    mode = settings["overwrite_mode"] || "replace"

    attrs =
      @series_fields
      # The name comes from the folder and drives scanning; keep it local.
      |> Enum.reject(&(&1 == :name))
      |> Enum.reduce(%{}, fn field, acc ->
        maybe_set(acc, field, Map.get(metadata, field), Map.get(series, field), mode)
      end)
      |> Map.merge(%{
        metadata_matched_at: NaiveDateTime.utc_now(:second),
        metadata_source: source_mod.key()
      })

    Repo.transaction(fn ->
      case Library.update_series(series, attrs) do
        {:ok, updated} ->
          Importer.upsert_external_ids(SeriesExternalId, :series_id, series.id, metadata[:external_ids] || [])

          if name = metadata[:publisher] do
            with {:ok, p} <- Library.get_or_create_publisher(name),
                 do: Library.link_publisher_to_series(series.id, p.id)
          end

          updated

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp maybe_set(acc, _field, new, _current, _mode) when new in [nil, "", []], do: acc
  defp maybe_set(acc, field, new, _current, "replace"), do: Map.put(acc, field, new)

  defp maybe_set(acc, field, new, current, _fill) do
    if current in [nil, "", :unknown], do: Map.put(acc, field, new), else: acc
  end

  defp zero_to_nil(0), do: nil
  defp zero_to_nil(n), do: n

  defp maybe_put_imprint(attrs, %{publisher: pub, imprint: imprint})
       when is_binary(pub) and is_binary(imprint) and imprint != "" do
    with {:ok, publisher} <- Library.get_or_create_publisher(pub) do
      imprint =
        Repo.get_by(Imprint, publisher_id: publisher.id, name: imprint) ||
          Repo.insert!(%Imprint{publisher_id: publisher.id, name: imprint},
            on_conflict: :nothing,
            conflict_target: [:publisher_id, :name]
          )

      case imprint do
        %Imprint{id: nil} -> attrs
        %Imprint{id: id} -> Map.put(attrs, :imprint_id, id)
      end
    else
      _ -> attrs
    end
  end

  defp maybe_put_imprint(attrs, _), do: attrs

  defp link_publisher(_book, _series, name) when name in [nil, ""], do: :ok

  defp link_publisher(book, series, name) do
    with {:ok, publisher} <- Library.get_or_create_publisher(name) do
      Library.link_publisher_to_book(book.id, publisher.id)
      if series, do: Library.link_publisher_to_series(series.id, publisher.id)
    end

    :ok
  end
end
