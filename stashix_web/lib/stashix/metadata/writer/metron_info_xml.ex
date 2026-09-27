defmodule Stashix.Metadata.Writer.MetronInfoXml do
  @moduledoc """
  Builds a MetronInfo.xml document (see docs/MetronInfo.schema.xml) from a book
  in the database. Element order follows the schema's xs:sequence.
  """
  import Stashix.Metadata.Writer.XML, only: [el: 2, el: 3, document: 1]

  alias Stashix.Repo
  alias Stashix.Library.Book

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

  def preloads, do: @preloads

  def build(%Book{} = book) do
    book = Repo.preload(book, @preloads)
    series = book.series

    el(
      "MetronInfo",
      [
        {"xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance"},
        {"xmlns:xsd", "http://www.w3.org/2001/XMLSchema"}
      ],
      [
        el(
          "IDS",
          Enum.map(book.external_ids, &el("ID", [{"source", &1.source}, {"primary", &1.is_primary}], &1.source_id))
        ),
        publisher(book),
        series(book, series),
        el("CollectionTitle", book.collection_title),
        el("Number", number(book.issue_number)),
        el("AlternativeNumber", book.alternative_number),
        el("Stories", stories(book)),
        el("Summary", book.summary),
        el("Prices", Enum.map(book.prices, &el("Price", [{"country", &1.country}], &1.amount))),
        el("CoverDate", book.cover_date),
        el("StoreDate", book.store_date),
        el("PageCount", if(book.page_count && book.page_count > 0, do: book.page_count)),
        el("Notes", book.notes),
        el("Genres", Enum.map(book.genres, &el("Genre", &1.name))),
        el("Tags", Enum.map(book.tags, &el("Tag", &1.name))),
        el("Arcs", Enum.map(book.story_arcs, &arc/1)),
        el("Characters", resources("Character", book.characters)),
        el("Teams", resources("Team", book.teams)),
        el("Universes", Enum.map(book.universes, &universe/1)),
        el("Locations", resources("Location", book.locations)),
        el("Reprints", resources("Reprint", book.reprints)),
        el("GTIN", [el("ISBN", book.isbn), el("UPC", book.upc)]),
        el("AgeRating", age_rating(book.age_rating)),
        community_rating(book),
        el("URLs", Enum.map(book.urls, &el("URL", [{"primary", if(&1.is_primary, do: "true")}], &1.url))),
        el("Credits", credits(book.credits)),
        el("LastModified", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())
      ]
    )
    |> document()
  end

  defp publisher(%{publishers: [p | _]} = book) do
    el("Publisher", [el("Name", p.name), book.imprint && el("Imprint", book.imprint.name)])
  end

  defp publisher(_), do: nil

  # Series is required by the schema; fall back to the book title for standalones.
  defp series(book, nil), do: el("Series", [{"lang", book.language}], [el("Name", book.title)])

  defp series(book, series) do
    series_id =
      Enum.find_value(series.external_ids, fn e -> if e.is_primary or e.source == :Metron, do: e.source_id end)

    el("Series", [{"lang", series.language || book.language}, {"id", series_id}], [
      el("Name", series.name),
      el("SortName", series.sort_name),
      el("Volume", series.volume || book.volume),
      el("Format", series.format),
      el("StartYear", series.start_year),
      el("IssueCount", if(series.issue_count && series.issue_count > 0, do: series.issue_count)),
      el("VolumeCount", if(series.volume_count && series.volume_count > 0, do: series.volume_count)),
      el(
        "AlternativeNames",
        Enum.map(series.alternative_names, &el("AlternativeName", [{"lang", &1.lang}, {"id", &1.external_id}], &1.name))
      )
    ])
  end

  defp number(nil), do: nil
  defp number(n), do: Stashix.Metadata.Matcher.format_number(n)

  # MetronInfo has no Title element; story names carry the title.
  defp stories(%{stories: [_ | _] = stories}), do: resources("Story", stories)
  defp stories(%{title: title}) when is_binary(title) and title != "", do: [el("Story", title)]
  defp stories(_), do: []

  defp resources(tag, items), do: Enum.map(items, &el(tag, [{"id", &1.external_id}], &1.name))

  defp arc(a), do: el("Arc", [{"id", a.external_id}], [el("Name", a.name), el("Number", a.arc_number)])

  defp universe(u),
    do: el("Universe", [{"id", u.external_id}], [el("Name", u.name), el("Designation", u.designation)])

  defp community_rating(%{community_rating: r} = book) when is_number(r) do
    el("CommunityRating", [
      el("AverageRating", :erlang.float_to_binary(r / 1, decimals: 1)),
      el(
        "RatingCount",
        if(book.community_rating_count && book.community_rating_count > 0, do: book.community_rating_count)
      )
    ])
  end

  defp community_rating(_), do: nil

  defp credits(credits) do
    credits
    |> Enum.group_by(& &1.creator)
    |> Enum.sort_by(fn {creator, _} -> creator.name end)
    |> Enum.map(fn {creator, rows} ->
      el("Credit", [
        el("Creator", creator.name),
        el("Roles", Enum.map(rows, &el("Role", role(&1.role))))
      ])
    end)
  end

  defp role(:"Cover Artist"), do: "Cover"
  defp role(r), do: to_string(r)

  @age_ratings %{
    everyone: "Everyone",
    teen: "Teen",
    teen_plus: "Teen Plus",
    mature: "Mature",
    adult: "Adult",
    explicit: "Explicit"
  }

  defp age_rating(r), do: Map.get(@age_ratings, r)
end
