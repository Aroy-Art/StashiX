defmodule Stashix.Metadata.Writer.ComicInfoXml do
  @moduledoc """
  Builds a ComicInfo.xml (Anansi v2.0) compatibility copy for readers that do
  not understand MetronInfo.
  """
  import Stashix.Metadata.Writer.XML, only: [el: 2, el: 3, document: 1]

  alias Stashix.Repo
  alias Stashix.Library.Book
  alias Stashix.Metadata.Writer.MetronInfoXml

  @role_fields [
    {"Writer", ~w(Writer Script Story Plot)a},
    {"Penciller", ~w(Penciller Artist Breakdowns Layouts Illustrator)a},
    {"Inker", ~w(Inker Artist Finishes Embellisher Illustrator)a},
    {"Colorist", ~w(Colorist)a},
    {"Letterer", ~w(Letterer)a},
    {"CoverArtist", [:"Cover Artist"]},
    {"Editor", ~w(Editor)a},
    {"Translator", ~w(Translator)a}
  ]

  def build(%Book{} = book) do
    book = Repo.preload(book, MetronInfoXml.preloads())
    series = book.series
    date = book.cover_date || book.store_date

    el(
      "ComicInfo",
      [
        {"xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance"},
        {"xmlns:xsd", "http://www.w3.org/2001/XMLSchema"}
      ],
      [
        el("Title", title(book)),
        el("Series", (series && series.name) || book.title),
        el("Number", book.issue_number && Stashix.Metadata.Matcher.format_number(book.issue_number)),
        el("Count", if(series && (series.issue_count || 0) > 0, do: series.issue_count)),
        el("Volume", (series && series.volume) || book.volume),
        el("AlternateNumber", book.alternative_number),
        el("StoryArc", join(book.story_arcs)),
        el("Summary", book.summary),
        el("Notes", book.notes),
        el("Year", (date && date.year) || book.year),
        el("Month", date && date.month),
        el("Day", date && date.day)
      ] ++
        Enum.map(@role_fields, fn {tag, roles} -> el(tag, creators(book.credits, roles)) end) ++
        [
          el("Publisher", List.first(Enum.map(book.publishers, & &1.name))),
          el("Imprint", book.imprint && book.imprint.name),
          el("Genre", join(book.genres)),
          el("Tags", join(book.tags)),
          el("Web", book.urls |> Enum.map(& &1.url) |> Enum.join(" ")),
          el("PageCount", if(book.page_count && book.page_count > 0, do: book.page_count)),
          el("LanguageISO", book.language),
          el("Format", series && series.format),
          el("Characters", join(book.characters)),
          el("Teams", join(book.teams)),
          el("Locations", join(book.locations)),
          el("CommunityRating", book.community_rating && Float.round(book.community_rating / 1, 1)),
          el("AgeRating", age_rating(book.age_rating)),
          el("GTIN", book.isbn || book.upc)
        ]
    )
    |> document()
  end

  defp title(%{stories: [_ | _] = stories}), do: stories |> Enum.map(& &1.name) |> Enum.join("; ")
  defp title(%{title: t}), do: t

  defp join(items), do: items |> Enum.map(& &1.name) |> Enum.uniq() |> Enum.join(", ")

  defp creators(credits, roles) do
    credits
    |> Enum.filter(&(&1.role in roles))
    |> Enum.map(& &1.creator.name)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  @age_ratings %{
    everyone: "Everyone",
    teen: "Teen",
    teen_plus: "Teen",
    mature: "Mature 17+",
    adult: "Adults Only 18+",
    explicit: "X18+"
  }

  defp age_rating(r), do: Map.get(@age_ratings, r)
end
