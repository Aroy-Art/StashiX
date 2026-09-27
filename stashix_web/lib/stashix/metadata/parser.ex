defmodule Stashix.Metadata.Parser do
  import SweetXml

  @noise_patterns ~w(
    Digital Webrip c2c HQ Retail
    HD 1080p 720p 480p
    FIXED Corrected v2 v3
    f2 f3
  )

  @noise_regex Regex.compile!(
                 "\\s*\\((?:#{Enum.join(@noise_patterns, "|")})\\)\\s*",
                 "i"
               )

  def parse_comicinfo(archive_path) do
    case parse_sidecar(archive_path) do
      nil -> parse_embedded(archive_path)
      sidecar -> Map.merge(parse_embedded(archive_path), sidecar)
    end
  end

  # A `<book name>.xml` next to the file (written by metadata write-back for
  # formats we can't embed into) takes precedence over embedded data.
  defp parse_sidecar(archive_path) do
    path = Path.rootname(archive_path) <> ".xml"

    with true <- File.regular?(path),
         {:ok, data} <- File.read(path) do
      cond do
        String.contains?(data, "<MetronInfo") -> parse_metroninfo_xml(data)
        String.contains?(data, "<ComicInfo") -> parse_comicinfo_xml(data)
        true -> nil
      end
    else
      _ -> nil
    end
  end

  defp parse_embedded(archive_path) do
    ext = archive_path |> Path.extname() |> String.downcase()

    case ext do
      cbz when cbz in [".cbz", ".epub"] ->
        case extract_xml_from_zip(archive_path) do
          nil ->
            %{}

          xmls ->
            # MetronInfo wins; ComicInfo fills fields MetronInfo lacks (e.g. Title).
            comic = if data = xmls[:comicinfo], do: parse_comicinfo_xml(data), else: %{}
            metron = if data = xmls[:metroninfo], do: parse_metroninfo_xml(data), else: %{}
            Map.merge(comic, metron)
        end

      ".pdf" ->
        parse_pdf_metadata(archive_path)

      _ ->
        %{}
    end
  end

  defp extract_xml_from_zip(archive_path) do
    path_charlist = String.to_charlist(archive_path)

    with {:ok, entries} <- :zip.list_dir(path_charlist) do
      xml_names =
        Enum.flat_map(entries, fn
          {:zip_file, name, _info, _comment, _offset, _comp_size} ->
            case to_string(name) |> String.downcase() do
              "comicinfo.xml" -> [{:comicinfo, name}]
              "metroninfo.xml" -> [{:metroninfo, name}]
              _ -> []
            end

          _ ->
            []
        end)

      if xml_names == [] do
        nil
      else
        case :zip.extract(path_charlist, [:memory, {:file_list, Enum.map(xml_names, &elem(&1, 1))}]) do
          {:ok, files} ->
            by_name = Map.new(files, fn {name, data} -> {to_string(name), data} end)
            Map.new(xml_names, fn {format, name} -> {format, by_name[to_string(name)]} end)

          _ ->
            nil
        end
      end
    else
      _ -> nil
    end
  end

  defp sanitize_xml(data) when is_binary(data) do
    # xmerl fatal on duplicate namespace declarations; deduplicate xmlns:* attrs
    Regex.replace(
      ~r/(<[A-Za-z][^>]*?)((\s+xmlns:[A-Za-z0-9_]+=("[^"]*"|'[^']*'))+)/,
      data,
      fn _, tag_open, ns_block, _, _ ->
        deduped =
          Regex.scan(~r/\s+xmlns:[A-Za-z0-9_]+=(?:"[^"]*"|'[^']*')/, ns_block)
          |> Enum.map(&hd/1)
          |> Enum.uniq_by(fn attr -> Regex.run(~r/xmlns:[A-Za-z0-9_]+/, attr) end)
          |> Enum.join("")

        tag_open <> deduped
      end
    )
  end

  defp parse_comicinfo_xml(data) when is_binary(data) do
    try do
      doc = data |> sanitize_xml() |> parse()

      age_rating_raw = xpath(doc, ~x"//ComicInfo/AgeRating/text()"s)

      %{}
      |> maybe_put(:title, xpath(doc, ~x"//ComicInfo/Title/text()"os))
      |> maybe_put(:series, xpath(doc, ~x"//ComicInfo/Series/text()"os))
      |> maybe_put(
        :issue_number,
        parse_decimal(xpath(doc, ~x"//ComicInfo/Number/text()"os))
      )
      |> maybe_put(:volume, parse_int(xpath(doc, ~x"//ComicInfo/Volume/text()"os)))
      |> maybe_put(:year, parse_int(xpath(doc, ~x"//ComicInfo/Year/text()"os)))
      |> maybe_put(:publisher, xpath(doc, ~x"//ComicInfo/Publisher/text()"os))
      |> maybe_put(:page_count, parse_int(xpath(doc, ~x"//ComicInfo/PageCount/text()"os)))
      |> maybe_put(:summary, xpath(doc, ~x"//ComicInfo/Summary/text()"os))
      |> maybe_put(:age_rating, normalize_age_rating(age_rating_raw))
      |> maybe_put(:language, xpath(doc, ~x"//ComicInfo/LanguageISO/text()"os))
      |> maybe_put(:genres, split_delimited(xpath(doc, ~x"//ComicInfo/Genre/text()"os)))
      |> maybe_put(:tags, split_delimited(xpath(doc, ~x"//ComicInfo/Tags/text()"os)))
      |> maybe_put(
        :arcs,
        case xpath(doc, ~x"//ComicInfo/StoryArc/text()"os) do
          s when s not in [nil, ""] -> [%{name: s, arc_number: nil, external_id: nil}]
          _ -> nil
        end
      )
    rescue
      _ -> %{}
    catch
      :exit, _ -> %{}
    end
  end

  defp parse_metroninfo_xml(data) when is_binary(data) do
    try do
      doc = data |> sanitize_xml() |> parse()

      age_rating_raw = xpath(doc, ~x"//MetronInfo/AgeRating/text()"s)
      cover_date = parse_date(xpath(doc, ~x"//MetronInfo/CoverDate/text()"os))
      store_date = parse_date(xpath(doc, ~x"//MetronInfo/StoreDate/text()"os))

      community_rating =
        case xpath(doc, ~x"//MetronInfo/CommunityRating/AverageRating/text()"os) do
          s when s not in [nil, ""] -> with {f, _} <- Float.parse(s), do: f
          _ -> nil
        end

      genres =
        xpath(doc, ~x"//MetronInfo/Genres/Genre/text()"ls)
        |> Enum.reject(&(&1 == ""))

      tags =
        xpath(doc, ~x"//MetronInfo/Tags/Tag/text()"ls)
        |> Enum.reject(&(&1 == ""))

      arcs =
        xpath(doc, ~x"//MetronInfo/Arcs/Arc"l,
          name: ~x"./Name/text()"s,
          arc_number: ~x"./Number/text()"os,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))
        |> Enum.map(&%{name: &1.name, arc_number: parse_int(&1.arc_number), external_id: &1.external_id})

      credits =
        xpath(doc, ~x"//MetronInfo/Credits/Credit"l,
          creator: ~x"./Creator/text()"s,
          creator_id: ~x"./Creator/@id"os,
          roles: ~x"./Roles/Role/text()"ls
        )
        |> Enum.reject(&(&1.creator == ""))

      characters =
        xpath(doc, ~x"//MetronInfo/Characters/Character"l,
          name: ~x"./text()"s,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      teams =
        xpath(doc, ~x"//MetronInfo/Teams/Team"l,
          name: ~x"./text()"s,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      universes =
        xpath(doc, ~x"//MetronInfo/Universes/Universe"l,
          name: ~x"./Name/text()"s,
          designation: ~x"./Designation/text()"os,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      locations =
        xpath(doc, ~x"//MetronInfo/Locations/Location"l,
          name: ~x"./text()"s,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      reprints =
        xpath(doc, ~x"//MetronInfo/Reprints/Reprint"l,
          name: ~x"./text()"s,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      stories =
        xpath(doc, ~x"//MetronInfo/Stories/Story"l,
          name: ~x"./text()"s,
          external_id: ~x"./@id"os
        )
        |> Enum.reject(&(&1.name == ""))

      urls =
        xpath(doc, ~x"//MetronInfo/URLs/URL"l,
          url: ~x"./text()"s,
          is_primary: ~x"./@primary"os
        )
        |> Enum.reject(&(&1.url == ""))
        |> Enum.map(&%{url: &1.url, is_primary: &1.is_primary == "true"})

      prices =
        xpath(doc, ~x"//MetronInfo/Prices/Price"l,
          amount: ~x"./text()"s,
          country: ~x"./@country"s
        )
        |> Enum.reject(&(&1.country == ""))
        |> Enum.map(&%{amount: parse_decimal(&1.amount), country: &1.country})
        |> Enum.reject(&is_nil(&1.amount))

      external_ids =
        xpath(doc, ~x"//MetronInfo/IDS/ID"l,
          source: ~x"./@source"s,
          source_id: ~x"./text()"s,
          is_primary: ~x"./@primary"os
        )
        |> Enum.reject(&(&1.source == "" || &1.source_id == ""))
        |> Enum.map(&%{source: &1.source, source_id: &1.source_id, is_primary: &1.is_primary == "true"})

      last_modified =
        case xpath(doc, ~x"//MetronInfo/LastModified/text()"os) do
          s when s not in [nil, ""] ->
            case NaiveDateTime.from_iso8601(s) do
              {:ok, dt} -> dt
              _ -> nil
            end

          _ ->
            nil
        end

      %{}
      |> maybe_put(:series, xpath(doc, ~x"//MetronInfo/Series/Name/text()"os))
      |> maybe_put(:series_sort_name, xpath(doc, ~x"//MetronInfo/Series/SortName/text()"os))
      |> maybe_put(:volume, parse_int(xpath(doc, ~x"//MetronInfo/Series/Volume/text()"os)))
      |> maybe_put(:series_format, xpath(doc, ~x"//MetronInfo/Series/Format/text()"os))
      |> maybe_put(:series_start_year, parse_int(xpath(doc, ~x"//MetronInfo/Series/StartYear/text()"os)))
      |> maybe_put(:series_issue_count, parse_int(xpath(doc, ~x"//MetronInfo/Series/IssueCount/text()"os)))
      |> maybe_put(:series_volume_count, parse_int(xpath(doc, ~x"//MetronInfo/Series/VolumeCount/text()"os)))
      |> maybe_put(:language, xpath(doc, ~x"//MetronInfo/Series/@lang"os))
      |> maybe_put(:issue_number, parse_decimal(xpath(doc, ~x"//MetronInfo/Number/text()"os)))
      |> maybe_put(:alternative_number, xpath(doc, ~x"//MetronInfo/AlternativeNumber/text()"os))
      |> maybe_put(:collection_title, xpath(doc, ~x"//MetronInfo/CollectionTitle/text()"os))
      |> maybe_put(:cover_date, cover_date)
      |> maybe_put(:store_date, store_date)
      |> maybe_put(:year, (cover_date && cover_date.year) || (store_date && store_date.year))
      |> maybe_put(:publisher, xpath(doc, ~x"//MetronInfo/Publisher/Name/text()"os))
      |> maybe_put(:imprint, xpath(doc, ~x"//MetronInfo/Publisher/Imprint/text()"os))
      |> maybe_put(:page_count, parse_int(xpath(doc, ~x"//MetronInfo/PageCount/text()"os)))
      |> maybe_put(:summary, xpath(doc, ~x"//MetronInfo/Summary/text()"os))
      |> maybe_put(:notes, xpath(doc, ~x"//MetronInfo/Notes/text()"os))
      |> maybe_put(:age_rating, normalize_metroninfo_age_rating(age_rating_raw))
      |> maybe_put(:isbn, xpath(doc, ~x"//MetronInfo/GTIN/ISBN/text()"os))
      |> maybe_put(:upc, xpath(doc, ~x"//MetronInfo/GTIN/UPC/text()"os))
      |> maybe_put(:community_rating, community_rating)
      |> maybe_put(
        :community_rating_count,
        parse_int(xpath(doc, ~x"//MetronInfo/CommunityRating/RatingCount/text()"os))
      )
      |> maybe_put(:last_modified, last_modified)
      |> maybe_put(:genres, if(genres != [], do: genres))
      |> maybe_put(:tags, if(tags != [], do: tags))
      |> maybe_put(:arcs, if(arcs != [], do: arcs))
      |> maybe_put(:credits, if(credits != [], do: credits))
      |> maybe_put(:characters, if(characters != [], do: characters))
      |> maybe_put(:teams, if(teams != [], do: teams))
      |> maybe_put(:universes, if(universes != [], do: universes))
      |> maybe_put(:locations, if(locations != [], do: locations))
      |> maybe_put(:reprints, if(reprints != [], do: reprints))
      |> maybe_put(:stories, if(stories != [], do: stories))
      # MetronInfo has no Title element; the first story name is the issue title.
      |> maybe_put(:title, if(stories != [], do: hd(stories).name))
      |> maybe_put(:urls, if(urls != [], do: urls))
      |> maybe_put(:prices, if(prices != [], do: prices))
      |> maybe_put(:external_ids, if(external_ids != [], do: external_ids))
    rescue
      _ -> %{}
    catch
      :exit, _ -> %{}
    end
  end

  defp normalize_metroninfo_age_rating("Everyone"), do: :everyone
  defp normalize_metroninfo_age_rating("Teen"), do: :teen
  defp normalize_metroninfo_age_rating("Teen Plus"), do: :teen_plus
  defp normalize_metroninfo_age_rating("Mature"), do: :mature
  defp normalize_metroninfo_age_rating("Explicit"), do: :explicit
  defp normalize_metroninfo_age_rating("Adult"), do: :adult
  defp normalize_metroninfo_age_rating("Unknown"), do: :unknown
  defp normalize_metroninfo_age_rating(_), do: nil

  defp parse_pdf_metadata(path) do
    try do
      case System.cmd("pdfinfo", [path], stderr_to_stdout: true) do
        {output, 0} ->
          fields =
            output
            |> String.split("\n", trim: true)
            |> Enum.reduce(%{}, fn line, acc ->
              case String.split(line, ":", parts: 2) do
                [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
                _ -> acc
              end
            end)

          year =
            case Map.get(fields, "CreationDate") do
              nil ->
                nil

              date ->
                Regex.run(~r/(\d{4})/, date)
                |> then(fn
                  [_, y] -> parse_int(y)
                  _ -> nil
                end)
            end

          %{}
          |> maybe_put(:title, Map.get(fields, "Title"))
          |> maybe_put(:page_count, parse_int(Map.get(fields, "Pages")))
          |> maybe_put(:year, year)

        _ ->
          %{}
      end
    rescue
      ErlangError -> %{}
    end
  end

  def parse_filename(filename) do
    source_format =
      case Regex.run(~r/\((Digital|Webrip|c2c|Retail|HQ)\)/i, filename) do
        [_, tag] -> String.downcase(tag)
        nil -> nil
      end

    clean =
      Regex.replace(@noise_regex, filename, " ")
      |> then(&Regex.replace(~r/\s*\(of\s+\d+\)\s*/i, &1, " "))
      |> then(&Regex.replace(~r/\((\d{1,2})-(\d{4})\)/, &1, "(\\2)"))
      |> String.trim()

    result = %{}

    # "Issue 6 - Angel of Death (1996)" or "Volume 3 - Killing Angel"
    result =
      case Regex.run(
             ~r/^(?:Issue|Vol(?:ume)?)\.?\s+(\d+)\s*(?:-|–)\s*(.+?)(?:\s*\((\d{4})\))?\s*$/i,
             clean
           ) do
        [_, num, title, year] ->
          result
          |> Map.put(:issue_number, parse_decimal(num))
          |> Map.put(:title, String.trim(title))
          |> maybe_put(:year, parse_int(year))

        [_, num, title] ->
          result
          |> Map.put(:issue_number, parse_decimal(num))
          |> Map.put(:title, String.trim(title))

        nil ->
          result
      end

    # "Series Vol. NN (YEAR)" or "Series Volume N" — e.g. Pariah Vol. 01 (2014), 9-11 Volume 2
    # Lookbehind prevents matching when dash immediately precedes "Vol." (handled by dash-Vol pattern below)
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)(?<![–\-])\s+Vol(?:ume)?\.?\s+(\d{1,4}(?:\.\d+)?)(?:\s+\((\d{4})\))?/i,
               clean
             ) do
          [_, series, volume | rest] ->
            year = Enum.at(rest, 0)

            result
            |> Map.put(:series, String.trim(series))
            |> maybe_put(:year, parse_int(year))
            |> Map.put(:volume, parse_int(volume))

          nil ->
            result
        end
      end

    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)\s+(\d{1,4})\s+\((\d{4})\)/i, clean) do
          [_, series, issue, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(issue))

          nil ->
            result
        end
      end

    # "Series NN (Publisher-YEAR)" — e.g. Jonny Demon 02 (Dark Horse-1994)
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)\s+(\d{1,4})\s+\([^)]*?(\d{4})[^)]*?\)/, clean) do
          [_, series, issue, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:year, String.to_integer(year))

          nil ->
            result
        end
      end

    # "Series #DATECODE - Vol. NNN[: Subtitle] (YEAR)" — e.g. Heavy Metal
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*(?:-|–)\s*Vol\.?\s+(\d+(?:\.\d+)?)(?:\s*:.*?)?\s*\((\d{4})\)/i,
               clean
             ) do
          [_, series, issue, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(issue))

          nil ->
            result
        end
      end

    # "Series - cNN Title (YEAR)" — e.g. Amulet - c01 The Stonekeeper (2008)
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*(?:-|–)\s*[#c](\d{1,4})\s+(.+?)\s*\((\d{4})\)/i,
               clean
             ) do
          [_, series, issue, title, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:title, String.trim(title))
            |> Map.put(:year, String.to_integer(year))

          nil ->
            result
        end
      end

    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:-|–)\s*(?:Chapter|Ch\.?)\s+(\d{1,4})/i,
               clean
             ) do
          [_, series, year, chapter] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(chapter))

          nil ->
            result
        end
      end

    # "Series - cNN - Title" — e.g. AKIRA - c001 - The Highway (no year)
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*(?:-|–)\s*[#c](\d{1,4})\s*(?:-|–)\s*(.+?)\s*$/i,
               clean
             ) do
          [_, series, issue, title] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:title, String.trim(title))

          nil ->
            result
        end
      end

    # "Series (YEAR) - Issue N" or "Series (YEAR) - Issue N - Title"
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:-|–)\s*(?:Issue|Iss\.?)\s+(\d+(?:\.\d+)?)/i,
               clean
             ) do
          [_, series, year, issue] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(issue))

          nil ->
            result
        end
      end

    # "Series NN - Title (Publisher YEAR) ..." e.g. "The Bank 01 - The Waterloo Insider (Cinebook 2025)"
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s+(\d{1,4}(?:\.\d+)?)\s*(?:-|–)\s*(.+?)\s*\([^)]*?(\d{4})[^)]*\)/,
               clean
             ) do
          [_, series, issue, title, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:title, String.trim(title))
            |> Map.put(:year, String.to_integer(year))

          nil ->
            result
        end
      end

    # "Series #NN (YEAR)" — e.g. "Clockwork Angels #06 (2014)"
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)\s+#(\d{1,4})[^(]*\((\d{4})\)/i, clean) do
          [_, series, issue, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:year, String.to_integer(year))

          nil ->
            result
        end
      end

    # "Series NN - Title" — e.g. "Asterix 11 - Asterix and the Chieftains Shield"
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s+(\d{1,4}(?:\.\d+)?)\s*(?:-|–)\s*(.+?)\s*$/,
               clean
             ) do
          [_, series, issue, title] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> Map.put(:title, String.trim(title))

          nil ->
            result
        end
      end

    result =
      if map_size(result) > 0 do
        result
      else
        match_filename_fallback(result, clean)
      end

    result = maybe_put(result, :source_format, source_format)

    if not Map.has_key?(result, :title) do
      Map.put_new(result, :title, Map.get(result, :series, clean))
    else
      result
    end
  end

  defp match_filename_fallback(result, clean) do
    with nil <- match_year_pattern(result, clean),
         nil <- match_volume_pattern(result, clean),
         nil <- match_issue_pattern(result, clean) do
      Map.put(result, :title, clean)
    end
  end

  defp match_year_pattern(result, clean) do
    with [_, series, year | rest] <-
           Regex.run(~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:v(\d+))?\s*(?:[#c]?(\d{1,4})(?:\.\d+)?)?/, clean) do
      result
      |> Map.put(:series, String.trim(series))
      |> Map.put(:year, String.to_integer(year))
      |> maybe_put(:volume, parse_int(Enum.at(rest, 0)))
      |> maybe_put(:issue_number, parse_decimal(Enum.at(rest, 1)))
    end
  end

  defp match_volume_pattern(result, clean) do
    with [_, series, volume | rest] <- Regex.run(~r/^(.+?)\s+v(\d+)\s+(?:[#c]?(\d{1,4})(?:\.\d+)?)?/i, clean) do
      result
      |> Map.put(:series, String.trim(series))
      |> maybe_put(:volume, parse_int(volume))
      |> maybe_put(:issue_number, parse_decimal(Enum.at(rest, 0)))
    end
  end

  defp match_issue_pattern(result, clean) do
    with [_, series, issue] <- Regex.run(~r/^(.+?)\s+[#c]?(\d{1,4})(?:\.\d+)?$/i, clean) do
      result
      |> Map.put(:series, String.trim(series))
      |> maybe_put(:issue_number, parse_decimal(issue))
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp split_delimited(nil), do: nil
  defp split_delimited(""), do: nil

  defp split_delimited(s) do
    result = s |> String.split(~r/[,|]/) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    if result == [], do: nil, else: result
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s),
    do: with({n, _} <- Integer.parse(s), do: n)

  defp parse_decimal(nil), do: nil
  defp parse_decimal(""), do: nil

  defp parse_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      {d, _} -> d
      :error -> nil
    end
  end

  defp normalize_age_rating("Everyone"), do: :everyone
  defp normalize_age_rating("Teen"), do: :teen
  defp normalize_age_rating("Teen+"), do: :teen_plus
  defp normalize_age_rating("Mature 17+"), do: :mature
  defp normalize_age_rating("Adults Only 18+"), do: :adult
  defp normalize_age_rating("X18+"), do: :explicit
  defp normalize_age_rating("Rating Pending"), do: :unknown
  defp normalize_age_rating(_), do: nil
end
