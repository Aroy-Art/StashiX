# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Record do
  @moduledoc """
  The one shape book metadata takes between the database and metadata files.

  `Stashix.Metadata.Format.MetronInfo` and `Stashix.Metadata.Format.ComicInfo`
  both parse into this map and build from it, so a value written by one side
  reads back identically on the other (see the round-trip tests). The scanner
  and `Stashix.Metadata.Importer` consume the same keys.

  All keys are optional; absent means "the file says nothing about it".

  Book scalars:
    `:title`, `:issue_number` (Decimal), `:alternative_number`,
    `:collection_title`, `:manga_volume`, `:volume`, `:year`, `:cover_date`,
    `:store_date`, `:summary`, `:notes`, `:page_count`, `:language`,
    `:age_rating` (`Stashix.Library.Book` enum atom), `:isbn`, `:upc`,
    `:community_rating` (float 0–5), `:community_rating_count`,
    `:publisher`, `:imprint`, `:last_modified`

  Series (`:series` is its name):
    `:series`, `:series_sort_name`, `:series_format`, `:series_start_year`,
    `:series_end_year`, `:series_status`, `:series_issue_count`,
    `:series_volume_count`, `:series_summary`, `:series_source_id`,
    `:series_alternative_names` (`[%{name, lang, external_id}]`)

  Lists:
    `:genres`, `:tags` (strings); `:stories`, `:characters`, `:teams`,
    `:locations`, `:reprints` (`[%{name, external_id}]`); `:arcs`
    (`[%{name, arc_number, external_id}]`); `:universes`
    (`[%{name, designation, external_id}]`); `:credits`
    (`[%{creator, roles: [String.t()]}]`, roles named as in
    `Stashix.Library.BookCredit`); `:urls` (`[%{url, is_primary}]`);
    `:prices` (`[%{amount: Decimal, country}]`); `:external_ids`
    (`[%{source: String.t(), source_id, is_primary}]`)

  ComicInfo-only extras (no DB column yet, kept so they survive a read):
    `:manga` (`"Yes" | "No" | "YesAndRightToLeft"`), `:black_and_white`,
    `:alternate_series`, `:alternate_count`, `:series_group`,
    `:main_character_or_team`, `:scan_information`, `:review`
  """

  alias Stashix.Repo
  alias Stashix.Library.Book

  @type t :: map()

  @preloads [
    :publishers,
    :imprint,
    :external_ids,
    :genres,
    :tags,
    :story_arcs,
    :stories,
    :characters,
    :teams,
    :universes,
    :locations,
    :reprints,
    :urls,
    :prices,
    credits: :creator,
    series: [:external_ids, :alternative_names, :publishers]
  ]

  @doc "Associations `from_book/1` needs."
  def preloads, do: @preloads

  @doc "Builds a record from a book in the database."
  @spec from_book(Book.t()) :: t()
  def from_book(%Book{} = book) do
    book = Repo.preload(book, @preloads)
    series = book.series

    %{
      title: book.title,
      issue_number: book.issue_number,
      alternative_number: book.alternative_number,
      collection_title: book.collection_title,
      # A book's own value wins; the series' is only a fallback.
      volume: book.volume || (series && series.volume),
      language: book.language || (series && series.language),
      year: book.year,
      cover_date: book.cover_date,
      store_date: book.store_date,
      summary: book.summary,
      notes: book.notes,
      page_count: if(book.page_count && book.page_count > 0, do: book.page_count),
      age_rating: if(book.age_rating != :unknown, do: book.age_rating),
      isbn: book.isbn,
      upc: book.upc,
      community_rating: book.community_rating,
      community_rating_count: book.community_rating_count,
      publisher: book.publishers |> List.first() |> then(&(&1 && &1.name)),
      imprint: book.imprint && book.imprint.name,
      genres: Enum.map(book.genres, & &1.name),
      tags: Enum.map(book.tags, & &1.name),
      stories: Enum.map(book.stories, &resource/1),
      characters: Enum.map(book.characters, &resource/1),
      teams: Enum.map(book.teams, &resource/1),
      locations: Enum.map(book.locations, &resource/1),
      reprints: Enum.map(book.reprints, &resource/1),
      arcs: Enum.map(book.story_arcs, &%{name: &1.name, arc_number: &1.arc_number, external_id: &1.external_id}),
      universes: Enum.map(book.universes, &%{name: &1.name, designation: &1.designation, external_id: &1.external_id}),
      credits: credits(book.credits),
      urls: Enum.map(book.urls, &%{url: &1.url, is_primary: &1.is_primary}),
      prices: Enum.map(book.prices, &%{amount: &1.amount, country: &1.country}),
      external_ids:
        Enum.map(
          book.external_ids,
          &%{source: to_string(&1.source), source_id: &1.source_id, is_primary: &1.is_primary}
        )
    }
    |> Map.merge(series_fields(series))
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp series_fields(nil), do: %{}

  defp series_fields(series) do
    %{
      series: series.name,
      series_sort_name: series.sort_name,
      series_format: series.format && to_string(series.format),
      series_start_year: series.start_year,
      series_end_year: series.end_year,
      series_status: if(series.ongoing, do: "Ongoing"),
      series_issue_count: positive(series.issue_count),
      series_volume_count: positive(series.volume_count),
      series_summary: series.summary,
      series_source_id:
        Enum.find_value(series.external_ids, fn e -> if e.is_primary or e.source == :Metron, do: e.source_id end),
      series_alternative_names:
        Enum.map(series.alternative_names, &%{name: &1.name, lang: &1.lang, external_id: &1.external_id})
    }
  end

  defp resource(r), do: %{name: r.name, external_id: r.external_id}

  defp credits(credits) do
    credits
    |> Enum.group_by(& &1.creator)
    |> Enum.sort_by(fn {creator, _} -> creator.name end)
    |> Enum.map(fn {creator, rows} -> %{creator: creator.name, roles: Enum.map(rows, &to_string(&1.role))} end)
  end

  defp positive(n) when is_integer(n) and n > 0, do: n
  defp positive(_), do: nil
end
