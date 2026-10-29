# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.FormatTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.Format.{ComicInfo, MetronInfo}

  @now ~U[2026-10-29 12:00:00Z]

  # Everything both formats can carry, in the shape the readers return.
  @record %{
    title: "I Am Gotham, Part One",
    series: "Batman",
    issue_number: Decimal.new("1"),
    alternative_number: "51",
    volume: 3,
    language: "en",
    year: 2016,
    cover_date: ~D[2016-08-01],
    summary: "A <b>bold</b> & brave tale",
    notes: "Tagged by Stashix",
    page_count: 24,
    age_rating: :teen,
    publisher: "DC Comics",
    imprint: "DC Black Label",
    series_format: "Single Issue",
    series_issue_count: 85,
    community_rating: 4.5,
    genres: ["Super-Hero", "Crime"],
    characters: [%{name: "Batman", external_id: nil}, %{name: "Gotham", external_id: nil}],
    teams: [%{name: "Justice League", external_id: nil}],
    locations: [%{name: "Gotham City", external_id: nil}],
    arcs: [%{name: "I Am Gotham", arc_number: 1, external_id: nil}],
    urls: [%{url: "https://comicvine.gamespot.com/batman-1/4000-525161/", is_primary: false}],
    credits: [
      %{creator: "David Finch", roles: ["Penciller"]},
      %{creator: "Tom King", roles: ["Writer"]}
    ]
  }

  defp ok!({:ok, r}), do: r

  defp tags(xml, root) do
    Regex.scan(~r/^  <([A-Za-z]+)[ >]/m, xml) |> Enum.map(&Enum.at(&1, 1)) |> tap(fn _ -> assert xml =~ "<#{root}" end)
  end

  describe "MetronInfo" do
    @metron Map.merge(@record, %{
              stories: [%{name: "I Am Gotham, Part One", external_id: "9"}],
              store_date: ~D[2016-06-15],
              isbn: "9781401267773",
              upc: "76194134182800111",
              series_sort_name: "Batman",
              series_start_year: 2016,
              series_end_year: 2020,
              series_status: "Completed",
              series_summary: "Rebirth run",
              series_volume_count: 3,
              series_source_id: "100",
              series_alternative_names: [%{name: "Batman (Rebirth)", lang: "en", external_id: nil}],
              collection_title: "Rebirth",
              manga_volume: "1",
              community_rating_count: 12,
              tags: ["rebirth"],
              universes: [%{name: "Earth 0", designation: "Prime", external_id: "4"}],
              reprints: [%{name: "Batman Rebirth Deluxe", external_id: nil}],
              prices: [%{amount: Decimal.new("2.99"), country: "US"}],
              external_ids: [%{source: "Metron", source_id: "111", is_primary: true}],
              credits: [
                %{creator: "David Finch", creator_id: "7", roles: ["Penciller", "Cover"]},
                %{creator: "Tom King", creator_id: nil, roles: ["Writer"]}
              ]
            })

    test "v1.2 round-trips every field" do
      xml = MetronInfo.build(@metron, now: @now)
      assert xml =~ "<LastModified>2026-10-29T12:00:00Z</LastModified>"
      parsed = xml |> MetronInfo.parse() |> ok!()

      for {key, value} <- @metron do
        assert parsed[key] == value, "#{key}: #{inspect(parsed[key])} != #{inspect(value)}"
      end

      assert parsed.last_modified == ~N[2026-10-29 12:00:00]
    end

    test "older versions leave out newer elements" do
      v10 = MetronInfo.build(@metron, version: "1.0")
      refute v10 =~ "<AlternativeNumber>"
      refute v10 =~ "<CommunityRating>"
      refute v10 =~ "<EndYear>"
      assert MetronInfo.detect_version(v10) == "1.0"

      v11 = MetronInfo.build(@metron, version: "1.1")
      assert v11 =~ "<AlternativeNumber>51</AlternativeNumber>"
      refute v11 =~ "<Status>"
      assert MetronInfo.detect_version(v11) == "1.1"

      assert MetronInfo.detect_version(MetronInfo.build(@metron)) == "1.2"
    end

    test "language tags are narrowed before v1.2" do
      r = %{@metron | language: "pt-BR"}
      assert MetronInfo.build(r) =~ ~s(lang="pt-BR")
      assert MetronInfo.build(r, version: "1.1") =~ ~s(lang="pt")
    end

    test "values outside the schema enums are coerced or dropped" do
      r = %{
        title: "X",
        series_format: "Treasury",
        series_status: "Ongoing",
        series_end_year: 2020,
        external_ids: [
          %{source: "Unknown", source_id: "1", is_primary: true},
          %{source: "Comic Vine", source_id: "2", is_primary: true},
          %{source: "Metron", source_id: "3", is_primary: true}
        ],
        credits: [%{creator: "A", roles: ["Cover Artist", "Editor in Chief", "VP of Sales", "General Manager"]}]
      }

      xml = MetronInfo.build(r)
      refute xml =~ "Treasury"
      refute xml =~ "<EndYear>", "an ongoing series has no EndYear"
      refute xml =~ ~s(source="Unknown")
      assert length(Regex.scan(~r/primary="true"/, xml)) == 1
      assert xml =~ "<Role>Cover</Role>"
      assert xml =~ "<Role>Editor In Chief</Role>"
      assert length(Regex.scan(~r{<Role>Other</Role>}, xml)) == 1
    end

    test "standalones use the title as the required series name" do
      assert %{series: "Smoke/Ashes"} = %{title: "Smoke/Ashes"} |> MetronInfo.build() |> MetronInfo.parse() |> ok!()
    end

    test "format-label stories fall back to the series name" do
      xml = "<MetronInfo><Series><Name>Smoke/Ashes</Name></Series><Stories><Story>TPB/HC</Story></Stories></MetronInfo>"
      assert %{title: "Smoke/Ashes"} = ok!(MetronInfo.parse(xml))
    end

    test "rejects other documents" do
      assert {:error, :not_metroninfo} = MetronInfo.parse("<ComicInfo/>")
      assert {:error, _} = MetronInfo.parse("not xml")
    end
  end

  describe "ComicInfo" do
    @comic Map.merge(@record, %{
             tags: ["rebirth"],
             isbn: "9781401267773",
             credits: [
               %{creator: "David Finch", roles: ["Penciller", "Cover Artist"]},
               %{creator: "Jane Doe", roles: ["Translator"]},
               %{creator: "Tom King", roles: ["Writer"]}
             ],
             arcs: [
               %{name: "I Am Gotham", arc_number: 1, external_id: nil},
               %{name: "Rebirth", arc_number: 3, external_id: nil}
             ],
             manga: "YesAndRightToLeft",
             black_and_white: "No",
             series_group: "Bat-family",
             scan_information: "Digital",
             main_character_or_team: "Batman",
             review: "Great",
             alternate_series: "Detective Comics",
             alternate_count: 12
           })

    # Keys the reader derives instead of copying.
    @derived [:external_ids]

    test "v2.1 round-trips every field" do
      parsed = @comic |> ComicInfo.build(version: "2.1") |> ComicInfo.parse() |> ok!()

      for {key, value} <- Map.drop(@comic, @derived) do
        assert parsed[key] == value, "#{key}: #{inspect(parsed[key])} != #{inspect(value)}"
      end

      assert [%{source: "Comic Vine", source_id: "525161"}] = parsed.external_ids
    end

    test "elements follow the schema sequence" do
      sequence =
        ~w(Title Series Number Count Volume AlternateSeries AlternateNumber AlternateCount Summary Notes Year Month Day) ++
          ~w(Writer Penciller Inker Colorist Letterer CoverArtist Editor Translator Publisher Imprint Genre Tags Web) ++
          ~w(PageCount LanguageISO Format BlackAndWhite Manga Characters Teams Locations ScanInformation StoryArc) ++
          ~w(StoryArcNumber SeriesGroup AgeRating Pages CommunityRating MainCharacterOrTeam Review GTIN)

      for v <- ComicInfo.versions() do
        written = @comic |> ComicInfo.build(version: v) |> tags("ComicInfo")
        assert written == Enum.filter(sequence, &(&1 in written)), "v#{v} out of order: #{inspect(written)}"
      end
    end

    test "each version writes only its own elements" do
      v10 = ComicInfo.build(@comic, version: "1.0")
      assert ComicInfo.detect_version(v10) == "1.0"

      for tag <- ~w(Day Characters AgeRating CommunityRating StoryArc Translator Tags GTIN),
          do: refute(v10 =~ "<#{tag}>")

      assert v10 =~ "<Manga>Yes</Manga>"

      v20 = ComicInfo.build(@comic)
      assert ComicInfo.detect_version(v20) == "2.0"
      assert v20 =~ "<Day>1</Day>"
      for tag <- ~w(Translator Tags GTIN StoryArcNumber), do: refute(v20 =~ "<#{tag}>")
      refute v20 =~ "Jane Doe", "translator has no field before 2.1"

      assert ComicInfo.detect_version(ComicInfo.build(@comic, version: "2.1")) == "2.1"
    end

    test "every age rating reads back as itself" do
      for rating <- [:everyone, :teen, :teen_plus, :mature, :adult, :explicit] do
        assert %{age_rating: ^rating} = %{age_rating: rating} |> ComicInfo.build() |> ComicInfo.parse() |> ok!()
      end
    end

    test "other spec age ratings map to the nearest rating" do
      for {value, expected} <- [
            {"G", :everyone},
            {"Everyone 10+", :everyone},
            {"MA15+", :mature},
            {"Rating Pending", :unknown}
          ] do
        assert %{age_rating: ^expected} = ok!(ComicInfo.parse("<ComicInfo><AgeRating>#{value}</AgeRating></ComicInfo>"))
      end
    end

    test "a year that disagrees with the date is written without month/day" do
      xml = ComicInfo.build(%{year: 2014, cover_date: ~D[2013-09-01]})
      assert xml =~ "<Year>2014</Year>"
      refute xml =~ "<Month>"
    end

    test "Web is space-separated, with legacy commas accepted" do
      urls = [%{url: "https://a.example/x y", is_primary: false}, %{url: "https://b.example/", is_primary: false}]
      assert ComicInfo.build(%{urls: urls}) =~ "<Web>https://a.example/x%20y https://b.example/</Web>"

      parsed = ok!(ComicInfo.parse("<ComicInfo><Web>https://a.example/,https://b.example/</Web></ComicInfo>"))
      assert Enum.map(parsed.urls, & &1.url) == ["https://a.example/", "https://b.example/"]
    end

    test "story arc numbers are only written when every arc has one" do
      arcs = [%{name: "A", arc_number: 1}, %{name: "B", arc_number: nil}]
      refute ComicInfo.build(%{arcs: arcs}, version: "2.1") =~ "<StoryArcNumber>"
    end

    test "GTIN is filed as ISBN or UPC by shape" do
      assert %{upc: "761941341828"} = ok!(ComicInfo.parse("<ComicInfo><GTIN>761941341828</GTIN></ComicInfo>"))
      assert %{isbn: "1401267777"} = ok!(ComicInfo.parse("<ComicInfo><GTIN>1-4012-6777-7</GTIN></ComicInfo>"))
    end

    test "a year-like Volume is ignored" do
      refute Map.has_key?(ok!(ComicInfo.parse("<ComicInfo><Volume>2016</Volume></ComicInfo>")), :volume)
    end
  end
end
