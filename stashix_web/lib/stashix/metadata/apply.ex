defmodule Stashix.Metadata.Apply do
  @moduledoc """
  Persists metadata fetched from a source onto a book or series.

  `overwrite_mode` (from `Stashix.Settings.metadata/0`):
    * `"fill"`    - only empty local fields are filled in (default)
    * `"replace"` - every field the source provides replaces the local value
  An explicit `fields: [...]` option (manual matching) overrides the mode.
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

  @doc "Field keys that can be chosen individually in the Identify dialog."
  def book_field_keys, do: @book_fields ++ [:issue_number, :page_count, :publisher, :imprint] ++ @child_keys
  def series_field_keys, do: List.delete(@series_fields, :name) ++ [:publisher]

  @doc """
  Applies issue-level metadata (the `fetch_issue/2` map) to a book.

  Options:
    * `:fields` - explicit list of field keys to write (replacing current
      values); everything else is left alone. Without it `overwrite_mode`
      from `settings` decides.
  """
  def apply_book(%Book{} = book, source_mod, metadata, settings, opts \\ []) do
    book = Repo.preload(book, [:series, :publishers, :files | Map.values(@child_assocs)])
    rule = rule(settings, opts, book_field_keys())

    attrs =
      @book_fields
      |> Enum.reduce(%{}, fn field, acc ->
        put_if(acc, field, Map.get(metadata, field), current_value(book, field), rule)
      end)
      # A known issue number / real page count from the file is only replaced when explicitly chosen.
      |> put_if(:issue_number, metadata[:issue_number], book.issue_number, fill_unless_chosen(rule))
      |> put_if(:page_count, metadata[:page_count], zero_to_nil(book.page_count), fill_unless_chosen(rule))
      |> maybe_put_imprint(metadata, book.imprint_id, rule)
      |> Map.merge(%{
        metadata_matched_at: NaiveDateTime.utc_now(:second),
        metadata_source: source_mod.key()
      })

    children =
      @child_keys
      |> Enum.filter(fn key ->
        Map.has_key?(metadata, key) and write?(rule, key, metadata[key], Map.get(book, @child_assocs[key]))
      end)
      |> then(&Map.take(metadata, &1))

    publisher =
      if write?(rule, :publisher, metadata[:publisher], Enum.map(book.publishers, & &1.name)),
        do: metadata[:publisher]

    Repo.transaction(fn ->
      with {:ok, updated} <- Library.update_book(book, attrs),
           {:ok, _} <- Importer.replace_book_metadata(updated, children, only_present: true) do
        Importer.upsert_external_ids(BookExternalId, :book_id, book.id, metadata[:external_ids] || [])
        link_publisher(updated, book.series, publisher)

        if book.series do
          apply_series_from_issue(book.series, metadata)
        end

        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # {:mode, "fill" | "replace"} or {:fields, MapSet} — see write?/4
  defp rule(settings, opts, allowed) do
    case Keyword.get(opts, :fields) do
      nil ->
        {:mode, settings["overwrite_mode"] || "fill"}

      fields ->
        {:fields, fields |> Enum.map(&to_field(&1, allowed)) |> Enum.reject(&is_nil/1) |> MapSet.new()}
    end
  end

  defp to_field(f, allowed) when is_atom(f), do: if(f in allowed, do: f)
  defp to_field(f, allowed) when is_binary(f), do: Enum.find(allowed, &(Atom.to_string(&1) == f))

  @doc false
  def write?(_rule, _field, new, _current) when new in [nil, "", [], :unknown], do: false
  def write?({:fields, chosen}, field, _new, _current), do: MapSet.member?(chosen, field)
  def write?({:mode, "replace"}, _field, _new, _current), do: true
  def write?({:mode, _fill}, _field, _new, current), do: not present?(current)

  # A known issue number / real page count from the file is only replaced when explicitly chosen.
  defp fill_unless_chosen({:mode, _}), do: {:mode, "fill"}
  defp fill_unless_chosen(rule), do: rule

  @doc """
  The book's current value for `field` as far as "fill empty" is concerned: a
  title that is just the file name (the scanner's fallback) counts as empty.
  """
  def current_value(%Book{} = book, :title) do
    book = Repo.preload(book, :files)
    stems = Enum.map(book.files, &Path.basename(&1.path, Path.extname(&1.path)))
    if book.title in stems, do: nil, else: book.title
  end

  def current_value(%Book{} = book, field), do: Map.get(book, field)

  def present?(v), do: v not in [nil, "", [], :unknown]

  defp put_if(acc, field, new, current, rule) do
    if write?(rule, field, new, current), do: Map.put(acc, field, new), else: acc
  end

  # Issue payloads carry some series info; only fill gaps, never rename folders' series.
  defp apply_series_from_issue(%Series{metadata_locked: true}, _), do: :ok

  defp apply_series_from_issue(%Series{} = series, metadata) do
    attrs =
      %{}
      |> put_if(:sort_name, metadata[:series_sort_name], series.sort_name, {:mode, "fill"})
      |> put_if(:format, metadata[:series_format], series.format, {:mode, "fill"})
      |> put_if(:start_year, metadata[:series_start_year], series.start_year, {:mode, "fill"})
      |> put_if(:volume, metadata[:volume], series.volume, {:mode, "fill"})

    if attrs != %{}, do: Library.update_series(series, attrs)

    Importer.upsert_external_ids(
      SeriesExternalId,
      :series_id,
      series.id,
      metadata[:series_external_ids] || []
    )
  end

  @doc "Applies series-level metadata (the `fetch_series/2` map) to a series. Takes `:fields` like `apply_book/5`."
  def apply_series(%Series{} = series, source_mod, metadata, settings, opts \\ []) do
    series = Repo.preload(series, :publishers)
    rule = rule(settings, opts, series_field_keys())

    attrs =
      @series_fields
      # The name comes from the folder and drives scanning; keep it local.
      |> Enum.reject(&(&1 == :name))
      |> Enum.reduce(%{}, fn field, acc ->
        put_if(acc, field, Map.get(metadata, field), Map.get(series, field), rule)
      end)
      |> Map.merge(%{
        metadata_matched_at: NaiveDateTime.utc_now(:second),
        metadata_source: source_mod.key()
      })

    publisher =
      if write?(rule, :publisher, metadata[:publisher], Enum.map(series.publishers, & &1.name)),
        do: metadata[:publisher]

    Repo.transaction(fn ->
      case Library.update_series(series, attrs) do
        {:ok, updated} ->
          Importer.upsert_external_ids(SeriesExternalId, :series_id, series.id, metadata[:external_ids] || [])

          if publisher do
            with {:ok, p} <- Library.get_or_create_publisher(publisher),
                 do: Library.link_publisher_to_series(series.id, p.id)
          end

          updated

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp zero_to_nil(0), do: nil
  defp zero_to_nil(n), do: n

  defp maybe_put_imprint(attrs, %{publisher: pub, imprint: imprint}, current_id, rule)
       when is_binary(pub) and is_binary(imprint) and imprint != "" do
    with true <- write?(rule, :imprint, imprint, current_id),
         {:ok, publisher} <- Library.get_or_create_publisher(pub) do
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

  defp maybe_put_imprint(attrs, _, _, _), do: attrs

  defp link_publisher(_book, _series, name) when name in [nil, ""], do: :ok

  defp link_publisher(book, series, name) do
    with {:ok, publisher} <- Library.get_or_create_publisher(name) do
      Library.link_publisher_to_book(book.id, publisher.id)
      if series, do: Library.link_publisher_to_series(series.id, publisher.id)
    end

    :ok
  end
end
