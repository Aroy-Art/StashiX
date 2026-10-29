# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Format.MetronInfo do
  @moduledoc """
  Reads and writes MetronInfo.xml (https://metron-project.github.io/docs/metroninfo).

  Supported schema versions: #{Enum.join(~w(1.0 1.1 1.2), ", ")}.

    * `parse/1` accepts any version (the union of all elements) and returns a
      `Stashix.Metadata.Record` map.
    * `build/2` writes the requested version (default `"1.2"`): only elements
      that version defines, with values coerced to its enums and patterns.

  Version differences:

    * 1.1 adds `AlternativeNumber` and `CommunityRating`.
    * 1.2 adds `Series/EndYear`, `Series/Status`, `Series/Summary`, and widens
      `lang` from two lowercase letters to a BCP 47 tag.

  MetronInfo has no Title element: story names carry the title, and the first
  story is read as the book title. `build/2` therefore always leads `<Stories>`
  with the record's title.
  """
  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]
  import Stashix.Metadata.Format.XML

  alias Stashix.Metadata.Record

  @versions ~w(1.0 1.1 1.2)
  @latest "1.2"

  def versions, do: @versions
  def latest, do: @latest

  @sources ["AniList", "Comic Vine", "Grand Comics Database", "Kitsu", "MangaDex", "MangaUpdates"] ++
             ["Marvel", "Metron", "MyAnimeList", "League of Comic Geeks"]

  @formats ["Annual", "Digital Chapter", "Graphic Novel", "Hardcover", "Limited Series", "Omnibus"] ++
             ["One-Shot", "Single Issue", "Trade Paperback"]

  @statuses ~w(Cancelled Completed Hiatus Ongoing)

  @roles ["Writer", "Script", "Story", "Plot", "Interviewer", "Artist", "Penciller", "Breakdowns"] ++
           ["Illustrator", "Layouts", "Inker", "Embellisher", "Finishes", "Ink Assists", "Colorist"] ++
           ["Color Separations", "Color Assists", "Color Flats", "Digital Art Technician", "Gray Tone"] ++
           ["Letterer", "Cover", "Editor", "Consulting Editor", "Assistant Editor", "Associate Editor"] ++
           ["Group Editor", "Senior Editor", "Managing Editor", "Collection Editor", "Production"] ++
           ["Designer", "Logo Design", "Translator", "Supervising Editor", "Executive Editor"] ++
           ["Editor In Chief", "President", "Publisher", "Chief Creative Officer", "Executive Producer", "Other"]

  @role_lookup Map.new(@roles, &{String.downcase(&1), &1})

  @age_ratings %{
    everyone: "Everyone",
    teen: "Teen",
    teen_plus: "Teen Plus",
    mature: "Mature",
    explicit: "Explicit",
    adult: "Adult"
  }
  @age_ratings_in Map.new(@age_ratings, fn {k, v} -> {String.downcase(v), k} end)
                  |> Map.put("unknown", :unknown)

  # Format labels taggers put into <Stories> instead of a real title.
  @format_descriptors ~w(tpb hc ogn gn annual special deluxe omnibus compendium digest hardcover paperback)

  ## Reading

  @doc "Parses MetronInfo XML of any supported version into a record."
  @spec parse(binary()) :: {:ok, Record.t()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    with {:ok, doc} <- parse_document(xml) do
      if xpath(doc, ~x"/MetronInfo"o), do: {:ok, read(doc)}, else: {:error, :not_metroninfo}
    end
  end

  @doc """
  The lowest schema version that defines every element in the document. A
  hint only: a v1.2 writer that left out the new elements reads as 1.0.
  """
  @spec detect_version(binary()) :: String.t() | nil
  def detect_version(xml) do
    with {:ok, doc} <- parse_document(xml), true <- xpath(doc, ~x"/MetronInfo"o) != nil do
      lang = xpath(doc, ~x"/MetronInfo/Series/@lang"s)

      cond do
        xpath(doc, ~x"/MetronInfo/Series/EndYear | /MetronInfo/Series/Status | /MetronInfo/Series/Summary"o) ->
          "1.2"

        lang != "" and not String.match?(lang, ~r/^[a-z][a-z]$/) ->
          "1.2"

        xpath(doc, ~x"/MetronInfo/AlternativeNumber | /MetronInfo/CommunityRating"o) ->
          "1.1"

        true ->
          "1.0"
      end
    else
      _ -> nil
    end
  end

  defp read(doc) do
    t = fn path -> doc |> xpath(path) |> blank_to_nil() end
    cover_date = parse_date(t.(~x"/MetronInfo/CoverDate/text()"os))
    store_date = parse_date(t.(~x"/MetronInfo/StoreDate/text()"os))
    series_name = t.(~x"/MetronInfo/Series/Name/text()"os)
    stories = resources(doc, ~x"/MetronInfo/Stories/Story"l)

    %{}
    |> put(:external_ids, external_ids(doc))
    |> put(:publisher, t.(~x"/MetronInfo/Publisher/Name/text()"os))
    |> put(:imprint, t.(~x"/MetronInfo/Publisher/Imprint/text()"os))
    |> put(:series, series_name)
    |> put(:series_source_id, t.(~x"/MetronInfo/Series/@id"os))
    |> put(:language, t.(~x"/MetronInfo/Series/@lang"os))
    |> put(:series_sort_name, t.(~x"/MetronInfo/Series/SortName/text()"os))
    |> put(:volume, parse_int(t.(~x"/MetronInfo/Series/Volume/text()"os)))
    |> put(:series_format, t.(~x"/MetronInfo/Series/Format/text()"os))
    |> put(:series_start_year, parse_int(t.(~x"/MetronInfo/Series/StartYear/text()"os)))
    |> put(:series_end_year, parse_int(t.(~x"/MetronInfo/Series/EndYear/text()"os)))
    |> put(:series_status, t.(~x"/MetronInfo/Series/Status/text()"os))
    |> put(:series_issue_count, parse_int(t.(~x"/MetronInfo/Series/IssueCount/text()"os)))
    |> put(:series_volume_count, parse_int(t.(~x"/MetronInfo/Series/VolumeCount/text()"os)))
    |> put(:series_summary, t.(~x"/MetronInfo/Series/Summary/text()"os))
    |> put(:series_alternative_names, alternative_names(doc))
    |> put(:manga_volume, t.(~x"/MetronInfo/MangaVolume/text()"os))
    |> put(:collection_title, t.(~x"/MetronInfo/CollectionTitle/text()"os))
    |> put(:issue_number, parse_decimal(t.(~x"/MetronInfo/Number/text()"os)))
    |> put(:alternative_number, t.(~x"/MetronInfo/AlternativeNumber/text()"os))
    |> put(:stories, stories)
    |> put(:title, title(stories, series_name))
    |> put(:summary, t.(~x"/MetronInfo/Summary/text()"os))
    |> put(:prices, prices(doc))
    |> put(:cover_date, cover_date)
    |> put(:store_date, store_date)
    # No Year element; derive it from the dates.
    |> put(:year, (cover_date && cover_date.year) || (store_date && store_date.year))
    |> put(:page_count, parse_int(t.(~x"/MetronInfo/PageCount/text()"os)))
    |> put(:notes, t.(~x"/MetronInfo/Notes/text()"os))
    |> put(:genres, texts(doc, ~x"/MetronInfo/Genres/Genre/text()"ls))
    |> put(:tags, texts(doc, ~x"/MetronInfo/Tags/Tag/text()"ls))
    |> put(:arcs, arcs(doc))
    |> put(:characters, resources(doc, ~x"/MetronInfo/Characters/Character"l))
    |> put(:teams, resources(doc, ~x"/MetronInfo/Teams/Team"l))
    |> put(:universes, universes(doc))
    |> put(:locations, resources(doc, ~x"/MetronInfo/Locations/Location"l))
    |> put(:reprints, resources(doc, ~x"/MetronInfo/Reprints/Reprint"l))
    |> put(:isbn, t.(~x"/MetronInfo/GTIN/ISBN/text()"os))
    |> put(:upc, t.(~x"/MetronInfo/GTIN/UPC/text()"os))
    |> put(:age_rating, Map.get(@age_ratings_in, String.downcase(t.(~x"/MetronInfo/AgeRating/text()"os) || "")))
    |> put(:community_rating, parse_float(t.(~x"/MetronInfo/CommunityRating/AverageRating/text()"os)))
    |> put(:community_rating_count, parse_int(t.(~x"/MetronInfo/CommunityRating/RatingCount/text()"os)))
    |> put(:urls, urls(doc))
    |> put(:credits, credits(doc))
    |> put(:last_modified, last_modified(t.(~x"/MetronInfo/LastModified/text()"os)))
  end

  # The first story is the title unless it's only a format label (alone or
  # combined, e.g. "TPB/HC"); standalones then fall back to the series name.
  defp title([], series_name), do: series_name

  defp title([%{name: name} | _], series_name) do
    if format_descriptor?(name), do: series_name, else: name
  end

  defp format_descriptor?(name) do
    name
    |> String.downcase()
    |> String.split("/")
    |> Enum.all?(&(String.trim(&1) in @format_descriptors))
  end

  defp texts(doc, path), do: doc |> xpath(path) |> Enum.map(&blank_to_nil/1) |> Enum.reject(&is_nil/1)

  defp resources(doc, path) do
    doc
    |> xpath(path, name: ~x"./text()"s, external_id: ~x"./@id"os)
    |> Enum.flat_map(fn r ->
      case blank_to_nil(r.name) do
        nil -> []
        name -> [%{name: name, external_id: blank_to_nil(r.external_id)}]
      end
    end)
  end

  defp alternative_names(doc) do
    doc
    |> xpath(~x"/MetronInfo/Series/AlternativeNames/AlternativeName"l,
      name: ~x"./text()"s,
      lang: ~x"./@lang"os,
      external_id: ~x"./@id"os
    )
    |> Enum.flat_map(fn a ->
      case blank_to_nil(a.name) do
        nil -> []
        name -> [%{name: name, lang: blank_to_nil(a.lang) || "en", external_id: blank_to_nil(a.external_id)}]
      end
    end)
  end

  defp arcs(doc) do
    doc
    |> xpath(~x"/MetronInfo/Arcs/Arc"l, name: ~x"./Name/text()"s, arc_number: ~x"./Number/text()"os, id: ~x"./@id"os)
    |> Enum.flat_map(fn a ->
      case blank_to_nil(a.name) do
        nil -> []
        name -> [%{name: name, arc_number: parse_int(a.arc_number), external_id: blank_to_nil(a.id)}]
      end
    end)
  end

  defp universes(doc) do
    doc
    |> xpath(~x"/MetronInfo/Universes/Universe"l,
      name: ~x"./Name/text()"s,
      designation: ~x"./Designation/text()"os,
      id: ~x"./@id"os
    )
    |> Enum.flat_map(fn u ->
      case blank_to_nil(u.name) do
        nil -> []
        name -> [%{name: name, designation: blank_to_nil(u.designation), external_id: blank_to_nil(u.id)}]
      end
    end)
  end

  defp credits(doc) do
    doc
    |> xpath(~x"/MetronInfo/Credits/Credit"l,
      creator: ~x"./Creator/text()"s,
      creator_id: ~x"./Creator/@id"os,
      roles: ~x"./Roles/Role/text()"ls
    )
    |> Enum.flat_map(fn c ->
      case blank_to_nil(c.creator) do
        nil -> []
        name -> [%{creator: name, creator_id: blank_to_nil(c.creator_id), roles: Enum.map(c.roles, &String.trim/1)}]
      end
    end)
  end

  defp urls(doc) do
    doc
    |> xpath(~x"/MetronInfo/URLs/URL"l, url: ~x"./text()"s, primary: ~x"./@primary"os)
    |> Enum.map(&%{url: String.trim(&1.url), is_primary: parse_bool(&1.primary)})
    |> Enum.filter(&String.starts_with?(&1.url, ["http://", "https://"]))
  end

  defp prices(doc) do
    doc
    |> xpath(~x"/MetronInfo/Prices/Price"l, amount: ~x"./text()"s, country: ~x"./@country"s)
    |> Enum.map(&%{amount: parse_decimal(&1.amount), country: String.trim(&1.country)})
    |> Enum.reject(&(is_nil(&1.amount) or &1.country == ""))
  end

  defp external_ids(doc) do
    doc
    |> xpath(~x"/MetronInfo/IDS/ID"l, source: ~x"./@source"s, source_id: ~x"./text()"s, primary: ~x"./@primary"os)
    |> Enum.map(
      &%{source: String.trim(&1.source), source_id: String.trim(&1.source_id), is_primary: parse_bool(&1.primary)}
    )
    |> Enum.reject(&(&1.source == "" or &1.source_id == ""))
  end

  defp last_modified(nil), do: nil

  defp last_modified(s) do
    case NaiveDateTime.from_iso8601(s) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  ## Writing

  @doc """
  Builds MetronInfo XML from a record. Options:

    * `:version` - schema version to write (#{Enum.join(@versions, ", ")}),
      default `#{@latest}`.
    * `:now` - `LastModified` timestamp (default: current UTC time).
  """
  @spec build(Record.t(), keyword()) :: binary()
  def build(record, opts \\ []) do
    version = Keyword.get(opts, :version, @latest)
    unless version in @versions, do: raise(ArgumentError, "unsupported MetronInfo version #{inspect(version)}")
    since? = &(Version.compare(semver(version), semver(&1)) != :lt)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() |> DateTime.truncate(:second) end)
    r = record

    el("MetronInfo", [{"xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance"}], [
      el("IDS", build_ids(r[:external_ids] || [])),
      build_publisher(r),
      build_series(r, version, since?),
      el("MangaVolume", r[:manga_volume]),
      el("CollectionTitle", r[:collection_title]),
      el("Number", format_number(r[:issue_number])),
      if(since?.("1.1"), do: el("AlternativeNumber", r[:alternative_number])),
      el("Stories", build_stories(r[:title], r[:stories] || [])),
      el("Summary", r[:summary]),
      el("Prices", build_prices(r[:prices] || [])),
      el("CoverDate", r[:cover_date]),
      el("StoreDate", r[:store_date]),
      el("PageCount", non_negative(r[:page_count])),
      el("Notes", r[:notes]),
      el("Genres", Enum.map(r[:genres] || [], &el("Genre", &1))),
      el("Tags", Enum.map(r[:tags] || [], &el("Tag", &1))),
      el("Arcs", Enum.map(r[:arcs] || [], &build_arc/1)),
      el("Characters", build_resources("Character", r[:characters])),
      el("Teams", build_resources("Team", r[:teams])),
      el("Universes", Enum.map(r[:universes] || [], &build_universe/1)),
      el("Locations", build_resources("Location", r[:locations])),
      el("Reprints", build_resources("Reprint", r[:reprints])),
      el("GTIN", [el("ISBN", r[:isbn]), el("UPC", r[:upc])]),
      el("AgeRating", Map.get(@age_ratings, r[:age_rating])),
      if(since?.("1.1"), do: build_community_rating(r)),
      el("URLs", build_urls(r[:urls] || [])),
      el("Credits", build_credits(r[:credits] || [])),
      el("LastModified", now)
    ])
    |> document()
  end

  defp semver(v), do: Version.parse!(v <> ".0")

  # Only schema sources are valid, and at most one may be primary.
  defp build_ids(ids) do
    ids
    |> Enum.map(&%{&1 | source: to_string(&1.source)})
    |> Enum.filter(&(&1.source in @sources))
    |> Enum.uniq_by(& &1.source)
    |> only_one_primary()
    |> Enum.map(&el("ID", [{"source", &1.source}, {"primary", if(&1.is_primary, do: "true")}], &1.source_id))
  end

  defp only_one_primary(items) do
    {items, _} =
      Enum.map_reduce(items, false, fn item, seen ->
        primary = !!item[:is_primary] and not seen
        {Map.put(item, :is_primary, primary), seen or primary}
      end)

    items
  end

  defp build_publisher(%{publisher: name} = r) when is_binary(name) do
    el("Publisher", [el("Name", name), el("Imprint", r[:imprint])])
  end

  defp build_publisher(_), do: nil

  # Series is required; standalones fall back to the book title.
  defp build_series(r, version, since?) do
    status = if r[:series_status] in @statuses, do: r[:series_status]
    end_year = if status != "Ongoing", do: valid_end_year(r[:series_start_year], r[:series_end_year])

    el("Series", [{"lang", lang(r[:language], version)}, {"id", r[:series_source_id]}], [
      el("Name", r[:series] || r[:title]),
      el("SortName", r[:series_sort_name]),
      el("Volume", non_negative(r[:volume])),
      el("Format", if(r[:series_format] in @formats, do: r[:series_format])),
      el("StartYear", r[:series_start_year]),
      if(since?.("1.2"), do: el("EndYear", end_year)),
      if(since?.("1.2"), do: el("Status", status)),
      el("IssueCount", positive(r[:series_issue_count])),
      el("VolumeCount", positive(r[:series_volume_count])),
      el("AlternativeNames", Enum.map(r[:series_alternative_names] || [], &build_alt_name(&1, version))),
      if(since?.("1.2"), do: el("Summary", r[:series_summary]))
    ])
  end

  defp valid_end_year(start, end_year) when is_integer(start) and is_integer(end_year) and end_year < start, do: nil
  defp valid_end_year(_, end_year), do: end_year

  defp build_alt_name(a, version),
    do: el("AlternativeName", [{"lang", lang(a[:lang], version)}, {"id", a[:external_id]}], a.name)

  # Before 1.2 `lang` must be two lowercase letters; 1.2 takes a BCP 47 tag.
  defp lang(nil, _), do: nil

  defp lang(tag, "1.2") do
    if String.match?(tag, ~r/^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{1,8})*$/), do: tag
  end

  defp lang(tag, _) do
    case Regex.run(~r/^([a-zA-Z]{2})(?:-|$)/, tag) do
      [_, code] -> String.downcase(code)
      _ -> nil
    end
  end

  defp build_stories(title, stories) when is_binary(title) and title != "" do
    case Enum.split_with(stories, &(&1.name == title)) do
      {[story | _], rest} -> build_resources("Story", [story | rest])
      {[], rest} -> [el("Story", title) | build_resources("Story", rest)]
    end
  end

  defp build_stories(_, stories), do: build_resources("Story", stories)

  defp build_resources(_tag, nil), do: []
  defp build_resources(tag, items), do: Enum.map(items, &el(tag, [{"id", &1[:external_id]}], &1.name))

  defp build_prices(prices) do
    for %{amount: amount, country: country} <- prices,
        amount != nil,
        is_binary(country),
        country = String.upcase(country),
        String.match?(country, ~r/^[A-Z]{2}$/),
        do: el("Price", [{"country", country}], amount)
  end

  defp build_arc(a),
    do: el("Arc", [{"id", a[:external_id]}], [el("Name", a.name), el("Number", positive(a[:arc_number]))])

  defp build_universe(u),
    do: el("Universe", [{"id", u[:external_id]}], [el("Name", u.name), el("Designation", u[:designation])])

  defp build_community_rating(%{community_rating: rating} = r) when is_number(rating) and rating >= 0 and rating <= 5 do
    el("CommunityRating", [
      el("AverageRating", :erlang.float_to_binary(rating / 1, decimals: 1)),
      el("RatingCount", positive(r[:community_rating_count]))
    ])
  end

  defp build_community_rating(_), do: nil

  defp build_urls(urls) do
    urls
    |> Enum.filter(&String.starts_with?(&1.url, ["http://", "https://"]))
    |> only_one_primary()
    |> Enum.map(&el("URL", [{"primary", if(&1.is_primary, do: "true")}], &1.url))
  end

  defp build_credits(credits) do
    Enum.map(credits, fn c ->
      roles = c.roles |> Enum.map(&role_out/1) |> Enum.uniq()
      el("Credit", [el("Creator", [{"id", c[:creator_id]}], c.creator), el("Roles", Enum.map(roles, &el("Role", &1)))])
    end)
  end

  # Stashix stores the cover role as "Cover Artist"; roles outside the schema
  # enum (e.g. "VP of Sales") are written as Other.
  @doc false
  def role_out(role) do
    case role |> to_string() |> String.trim() |> String.downcase() do
      "cover artist" -> "Cover"
      key -> Map.get(@role_lookup, key, "Other")
    end
  end

  defp format_number(nil), do: nil
  defp format_number(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp format_number(n), do: to_string(n)

  defp non_negative(n) when is_integer(n) and n >= 0, do: n
  defp non_negative(_), do: nil

  defp positive(n) when is_integer(n) and n > 0, do: n
  defp positive(_), do: nil
end
