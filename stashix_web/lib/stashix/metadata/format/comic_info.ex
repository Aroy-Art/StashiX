# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Format.ComicInfo do
  @moduledoc """
  Reads and writes ComicInfo.xml (https://anansi-project.github.io/docs/comicinfo).

  Supported schema versions: 1.0, 2.0 (stable) and 2.1 (draft).

    * `parse/1` accepts any version and returns a `Stashix.Metadata.Record` map.
    * `build/2` writes the requested version (default `"2.0"`). ComicInfo is an
      `xs:sequence`, so elements are emitted in schema order, and only those the
      version defines.

  Version differences:

    * 2.0 adds Day, Characters, Teams, Locations, ScanInformation, StoryArc,
      SeriesGroup, AgeRating, CommunityRating, MainCharacterOrTeam, Review, and
      the `YesAndRightToLeft` Manga value.
    * 2.1 (draft) adds Translator, Tags, StoryArcNumber and GTIN.

  Multi-value fields are comma-separated, except `Web` which is
  space-separated. `StoryArc` and `StoryArcNumber` pair up by position.

  `<Pages>` is read into `:pages` (`[%{image: integer, type: "FrontCover …", …}]`)
  and written back as given; Stashix doesn't store it, but `FileWriter` carries
  it over from the archive's existing ComicInfo.xml.
  """
  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]
  import Stashix.Metadata.Format.XML

  alias Stashix.Metadata.Record

  @versions ~w(1.0 2.0 2.1)
  @default "2.0"

  def versions, do: @versions
  def default_version, do: @default

  # Schema order with the version each element first appears in.
  @sequence [
    {"Title", "1.0"},
    {"Series", "1.0"},
    {"Number", "1.0"},
    {"Count", "1.0"},
    {"Volume", "1.0"},
    {"AlternateSeries", "1.0"},
    {"AlternateNumber", "1.0"},
    {"AlternateCount", "1.0"},
    {"Summary", "1.0"},
    {"Notes", "1.0"},
    {"Year", "1.0"},
    {"Month", "1.0"},
    {"Day", "2.0"},
    {"Writer", "1.0"},
    {"Penciller", "1.0"},
    {"Inker", "1.0"},
    {"Colorist", "1.0"},
    {"Letterer", "1.0"},
    {"CoverArtist", "1.0"},
    {"Editor", "1.0"},
    {"Translator", "2.1"},
    {"Publisher", "1.0"},
    {"Imprint", "1.0"},
    {"Genre", "1.0"},
    {"Tags", "2.1"},
    {"Web", "1.0"},
    {"PageCount", "1.0"},
    {"LanguageISO", "1.0"},
    {"Format", "1.0"},
    {"BlackAndWhite", "1.0"},
    {"Manga", "1.0"},
    {"Characters", "2.0"},
    {"Teams", "2.0"},
    {"Locations", "2.0"},
    {"ScanInformation", "2.0"},
    {"StoryArc", "2.0"},
    {"StoryArcNumber", "2.1"},
    {"SeriesGroup", "2.0"},
    {"AgeRating", "2.0"},
    {"Pages", "1.0"},
    {"CommunityRating", "2.0"},
    {"MainCharacterOrTeam", "2.0"},
    {"Review", "2.0"},
    {"GTIN", "2.1"}
  ]

  @page_types ~w(FrontCover InnerCover Roundup Story Advertisement Editorial Letters Preview BackCover Other Deleted)

  @elements_2_0 for {name, "2.0"} <- @sequence, do: name
  @elements_2_1 for {name, "2.1"} <- @sequence, do: name

  # ComicInfo creator fields ↔ Stashix credit roles. Reading maps each field to
  # its first role; writing collects every role listed.
  @creator_fields [
    {"Writer", ~w(Writer Script Story Plot)},
    {"Penciller", ~w(Penciller Artist Breakdowns Layouts Illustrator)},
    {"Inker", ~w(Inker Artist Finishes Embellisher Illustrator)},
    {"Colorist", ~w(Colorist)},
    {"Letterer", ~w(Letterer)},
    {"CoverArtist", ["Cover Artist"]},
    {"Editor", ~w(Editor)},
    {"Translator", ~w(Translator)}
  ]

  # Written values are chosen so each rating reads back as itself; the other
  # spec values are mapped onto the nearest Stashix rating when read.
  @age_ratings_out %{
    everyone: "Everyone",
    teen: "Teen",
    teen_plus: "M",
    mature: "Mature 17+",
    adult: "Adults Only 18+",
    explicit: "X18+"
  }

  @age_ratings_in %{
    "unknown" => :unknown,
    "rating pending" => :unknown,
    "early childhood" => :everyone,
    "everyone" => :everyone,
    "everyone 10+" => :everyone,
    "g" => :everyone,
    "kids to adults" => :everyone,
    "pg" => :teen,
    "teen" => :teen,
    # Not in the spec, but written by older taggers.
    "teen+" => :teen_plus,
    "m" => :teen_plus,
    "ma15+" => :mature,
    "mature 17+" => :mature,
    "r18+" => :mature,
    "adults only 18+" => :adult,
    "x18+" => :explicit
  }

  ## Reading

  @doc "Parses ComicInfo XML of any supported version into a record."
  @spec parse(binary()) :: {:ok, Record.t()} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    with {:ok, doc} <- parse_document(xml) do
      if xpath(doc, ~x"/ComicInfo"o), do: {:ok, read(doc)}, else: {:error, :not_comicinfo}
    end
  end

  @doc "The lowest schema version that defines every element in the document."
  @spec detect_version(binary()) :: String.t() | nil
  def detect_version(xml) do
    with {:ok, doc} <- parse_document(xml), true <- xpath(doc, ~x"/ComicInfo"o) != nil do
      present = fn names -> Enum.any?(names, &xpath(doc, ~x"/ComicInfo/#{&1}"o)) end

      cond do
        present.(@elements_2_1) -> "2.1"
        present.(@elements_2_0) or xpath(doc, ~x"/ComicInfo/Manga/text()"s) == "YesAndRightToLeft" -> "2.0"
        true -> "1.0"
      end
    else
      _ -> nil
    end
  end

  defp read(doc) do
    t = fn name -> doc |> xpath(~x"/ComicInfo/#{name}/text()"os) |> blank_to_nil() end
    notes = t.("Notes")
    urls = split_web(t.("Web"))
    year = parse_int(t.("Year"))

    %{}
    |> put(:title, t.("Title"))
    |> put(:series, t.("Series"))
    |> put(:issue_number, parse_decimal(t.("Number")))
    |> put(:series_issue_count, positive(parse_int(t.("Count"))))
    |> put(:volume, volume(parse_int(t.("Volume"))))
    |> put(:alternate_series, t.("AlternateSeries"))
    |> put(:alternative_number, t.("AlternateNumber"))
    |> put(:alternate_count, positive(parse_int(t.("AlternateCount"))))
    |> put(:summary, t.("Summary"))
    |> put(:notes, notes)
    |> put(:year, year)
    |> put(:cover_date, date(year, parse_int(t.("Month")), parse_int(t.("Day"))))
    |> put(:credits, credits(t))
    |> put(:publisher, t.("Publisher"))
    |> put(:imprint, t.("Imprint"))
    |> put(:genres, split_list(t.("Genre")))
    |> put(:tags, split_list(t.("Tags")))
    |> put(:urls, Enum.map(urls, &%{url: &1, is_primary: false}))
    |> put(:external_ids, external_ids(urls, notes))
    |> put(:page_count, parse_int(t.("PageCount")))
    |> put(:language, t.("LanguageISO"))
    |> put(:series_format, t.("Format"))
    |> put(:black_and_white, yes_no(t.("BlackAndWhite")))
    |> put(:manga, yes_no(t.("Manga")))
    |> put(:characters, named(t.("Characters")))
    |> put(:teams, named(t.("Teams")))
    |> put(:locations, named(t.("Locations")))
    |> put(:scan_information, t.("ScanInformation"))
    |> put(:arcs, arcs(t.("StoryArc"), t.("StoryArcNumber")))
    |> put(:series_group, t.("SeriesGroup"))
    |> put(:age_rating, Map.get(@age_ratings_in, String.downcase(t.("AgeRating") || "")))
    |> put(:community_rating, rating(parse_float(t.("CommunityRating"))))
    |> put(:main_character_or_team, t.("MainCharacterOrTeam"))
    |> put(:review, t.("Review"))
    |> put(:pages, pages(doc))
    |> Map.merge(gtin(t.("GTIN")))
  end

  # Per-page info (cover, spreads, sizes) set by readers/taggers. Kept so a
  # rewrite of the archive doesn't lose it; invalid attributes are dropped.
  defp pages(doc) do
    doc
    |> xpath(~x"/ComicInfo/Pages/Page"l,
      image: ~x"./@Image"os,
      type: ~x"./@Type"os,
      double_page: ~x"./@DoublePage"os,
      image_size: ~x"./@ImageSize"os,
      key: ~x"./@Key"os,
      bookmark: ~x"./@Bookmark"os,
      image_width: ~x"./@ImageWidth"os,
      image_height: ~x"./@ImageHeight"os
    )
    |> Enum.flat_map(fn p ->
      case parse_int(p.image) do
        image when is_integer(image) and image >= 0 ->
          page =
            %{image: image}
            |> put(:type, page_types(p.type))
            |> put(:double_page, bool_attr(p.double_page))
            |> put(:image_size, parse_int(p.image_size))
            |> put(:key, blank_to_nil(p.key))
            |> put(:bookmark, blank_to_nil(p.bookmark))
            |> put(:image_width, parse_int(p.image_width))
            |> put(:image_height, parse_int(p.image_height))

          [page]

        _ ->
          []
      end
    end)
  end

  defp page_types(nil), do: nil

  defp page_types(s) do
    case s |> String.split() |> Enum.filter(&(&1 in @page_types)) do
      [] -> nil
      types -> Enum.join(types, " ")
    end
  end

  defp bool_attr(s) when s in ["true", "1"], do: "true"
  defp bool_attr(s) when s in ["false", "0"], do: "false"
  defp bool_attr(_), do: nil

  # ComicInfo allows a year as Volume ("Volume 2016"); Stashix volumes are numbers.
  defp volume(v) when is_integer(v) and v >= 1800 and v <= 2099, do: nil
  defp volume(v), do: v

  defp date(year, month, day) when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp date(_, _, _), do: nil

  defp credits(t) do
    @creator_fields
    |> Enum.flat_map(fn {field, [role | _]} -> Enum.map(split_list(t.(field)), &{&1, role}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {creator, roles} -> %{creator: creator, roles: Enum.uniq(roles)} end)
    |> Enum.sort_by(& &1.creator)
  end

  defp split_list(nil), do: []

  defp split_list(s) do
    s |> String.split(~r/[,|]/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp named(s), do: s |> split_list() |> Enum.map(&%{name: &1, external_id: nil})

  defp arcs(names, numbers) do
    numbers = split_list(numbers)

    names
    |> split_list()
    |> Enum.with_index()
    |> Enum.map(fn {name, i} -> %{name: name, arc_number: parse_int(Enum.at(numbers, i)), external_id: nil} end)
  end

  # Space-separated per spec; older taggers used commas.
  defp split_web(nil), do: []

  defp split_web(web) do
    web
    |> String.split(~r/\s+|,(?=\s*https?:\/\/)/, trim: true)
    |> Enum.filter(&String.starts_with?(&1, ["http://", "https://"]))
  end

  defp yes_no(v) when v in ["Yes", "No", "YesAndRightToLeft"], do: v
  defp yes_no(_), do: nil

  defp rating(r) when is_float(r) and r >= 0 and r <= 5, do: r
  defp rating(_), do: nil

  # GTIN may hold an ISBN, UPC, EAN, … — file it by shape.
  defp gtin(nil), do: %{}

  defp gtin(raw) do
    digits = String.replace(raw, ~r/[^0-9Xx]/, "")

    cond do
      String.length(digits) == 10 -> %{isbn: digits}
      String.length(digits) == 13 and String.starts_with?(digits, ["978", "979"]) -> %{isbn: digits}
      String.length(digits) in [12, 13] -> %{upc: digits}
      true -> %{}
    end
  end

  @doc """
  Source ids recoverable from ComicInfo's `Web` URLs and taggers' `Notes`
  (ComicTagger / MetronTagger write e.g. "... info from Comic Vine ... [Issue ID 12345]"
  or the older "[CVDB12345]").
  """
  def external_ids(urls, notes) do
    from_urls = Enum.flat_map(urls, &id_from_url/1)
    (from_urls ++ ids_from_notes(notes)) |> Enum.uniq_by(& &1.source)
  end

  defp id_from_url(url) do
    cond do
      m = Regex.run(~r{comicvine\.gamespot\.com/.*/4000-(\d+)}, url) ->
        [%{source: "Comic Vine", source_id: Enum.at(m, 1), is_primary: false}]

      m = Regex.run(~r{comics\.org/issue/(\d+)}, url) ->
        [%{source: "Grand Comics Database", source_id: Enum.at(m, 1), is_primary: false}]

      true ->
        []
    end
  end

  defp ids_from_notes(nil), do: []

  defp ids_from_notes(notes) do
    cvdb =
      case Regex.run(~r/\[CVDB(\d+)\]/i, notes) do
        [_, id] -> [%{source: "Comic Vine", source_id: id, is_primary: false}]
        _ -> []
      end

    issue_id =
      with [_, id] <- Regex.run(~r/\[Issue ID (\d+)\]/i, notes),
           source when not is_nil(source) <- notes_source(notes) do
        [%{source: source, source_id: id, is_primary: false}]
      else
        _ -> []
      end

    cvdb ++ issue_id
  end

  defp notes_source(notes) do
    cond do
      notes =~ ~r/from Metron/i -> "Metron"
      notes =~ ~r/from Comic ?Vine/i -> "Comic Vine"
      notes =~ ~r/from (GCD|Grand Comics Database)/i -> "Grand Comics Database"
      true -> nil
    end
  end

  ## Writing

  @doc """
  Builds ComicInfo XML from a record. Options:

    * `:version` - schema version to write (#{Enum.join(@versions, ", ")}),
      default `#{@default}`.
  """
  @spec build(Record.t(), keyword()) :: binary()
  def build(record, opts \\ []) do
    version = Keyword.get(opts, :version, @default)
    unless version in @versions, do: raise(ArgumentError, "unsupported ComicInfo version #{inspect(version)}")

    values = values(record, version)

    children =
      for {name, since} <- @sequence,
          Version.compare(semver(version), semver(since)) != :lt,
          do: el(name, Map.get(values, name))

    el(
      "ComicInfo",
      [{"xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance"}, {"xmlns:xsd", "http://www.w3.org/2001/XMLSchema"}],
      children
    )
    |> document()
  end

  defp semver(v), do: Version.parse!(v <> ".0")

  defp values(r, version) do
    date = r[:cover_date] || r[:store_date]
    year = r[:year] || (date && date.year)
    # Month/Day only when they belong to the year being written.
    date = if date && date.year == year, do: date
    arcs = r[:arcs] || []

    %{
      "Title" => r[:title],
      "Series" => r[:series] || r[:title],
      "Number" => format_number(r[:issue_number]),
      "Count" => positive(r[:series_issue_count]),
      "Volume" => r[:volume],
      "AlternateSeries" => r[:alternate_series],
      "AlternateNumber" => r[:alternative_number],
      "AlternateCount" => positive(r[:alternate_count]),
      "Summary" => r[:summary],
      "Notes" => r[:notes],
      "Year" => year,
      "Month" => date && date.month,
      "Day" => date && date.day,
      "Publisher" => r[:publisher],
      "Imprint" => r[:imprint],
      "Genre" => join(r[:genres]),
      "Tags" => join(r[:tags]),
      "Web" => web(r[:urls]),
      "PageCount" => r[:page_count],
      "LanguageISO" => r[:language],
      "Format" => r[:series_format],
      "BlackAndWhite" => r[:black_and_white],
      "Manga" => manga(r[:manga], version),
      "Characters" => join_names(r[:characters]),
      "Teams" => join_names(r[:teams]),
      "Locations" => join_names(r[:locations]),
      "ScanInformation" => r[:scan_information],
      "StoryArc" => join_names(arcs),
      "StoryArcNumber" => arc_numbers(arcs),
      "SeriesGroup" => r[:series_group],
      "AgeRating" => Map.get(@age_ratings_out, r[:age_rating]),
      "CommunityRating" => community_rating(r[:community_rating]),
      "MainCharacterOrTeam" => r[:main_character_or_team],
      "Review" => r[:review],
      "Pages" => Enum.map(r[:pages] || [], &build_page(&1, version)),
      "GTIN" => r[:isbn] || r[:upc]
    }
    |> Map.merge(creator_values(r[:credits] || []))
  end

  defp creator_values(credits) do
    Map.new(@creator_fields, fn {field, roles} ->
      names =
        credits
        |> Enum.filter(fn c -> Enum.any?(c.roles, &(to_string(&1) in roles)) end)
        |> Enum.map(& &1.creator)
        |> Enum.uniq()

      {field, join(names)}
    end)
  end

  defp join(nil), do: nil
  defp join(items), do: items |> Enum.uniq() |> Enum.join(", ")

  defp join_names(nil), do: nil
  defp join_names(items), do: items |> Enum.map(& &1.name) |> join()

  # Pairs with StoryArc by position, so only written when every arc has a number.
  defp arc_numbers([_ | _] = arcs) do
    numbers = Enum.map(arcs, & &1[:arc_number])
    if Enum.all?(numbers, &is_integer/1), do: Enum.join(numbers, ", ")
  end

  defp arc_numbers(_), do: nil

  defp web(nil), do: nil
  defp web(urls), do: urls |> Enum.map(&String.replace(&1.url, " ", "%20")) |> Enum.join(" ")

  defp build_page(page, version) do
    empty_el("Page", [
      {"Image", page.image},
      {"Type", page[:type]},
      {"DoublePage", page[:double_page]},
      {"ImageSize", page[:image_size]},
      {"Key", page[:key]},
      {"Bookmark", if(version != "1.0", do: page[:bookmark])},
      {"ImageWidth", page[:image_width]},
      {"ImageHeight", page[:image_height]}
    ])
  end

  defp manga("YesAndRightToLeft", "1.0"), do: "Yes"
  defp manga(v, _), do: v

  # One fraction digit is valid for both 2.0 (max 2) and 2.1 (max 1).
  defp community_rating(r) when is_number(r) and r >= 0 and r <= 5, do: :erlang.float_to_binary(r / 1, decimals: 1)
  defp community_rating(_), do: nil

  defp format_number(nil), do: nil
  defp format_number(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  defp format_number(n), do: to_string(n)

  defp positive(n) when is_integer(n) and n > 0, do: n
  defp positive(_), do: nil
end
