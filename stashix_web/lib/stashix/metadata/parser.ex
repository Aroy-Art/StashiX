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
    ext = archive_path |> Path.extname() |> String.downcase()

    case ext do
      cbz when cbz in [".cbz", ".epub"] ->
        case extract_xml_from_zip(archive_path) do
          nil -> %{}
          {:metroninfo, data} -> parse_metroninfo_xml(data)
          {:comicinfo, data} -> parse_comicinfo_xml(data)
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
      xml_entries =
        entries
        |> Enum.filter(fn
          {:zip_file, name, _info, _comment, _offset, _comp_size} ->
            n = to_string(name) |> String.downcase()
            n == "comicinfo.xml" || n == "metroninfo.xml"

          _ ->
            false
        end)

      # Prefer MetronInfo over ComicInfo when both exist
      xml_entry =
        Enum.find(xml_entries, fn {:zip_file, name, _, _, _, _} ->
          to_string(name) |> String.downcase() == "metroninfo.xml"
        end) || List.first(xml_entries)

      case xml_entry do
        nil ->
          nil

        {:zip_file, name, _info, _comment, _offset, _comp_size} ->
          format =
            if to_string(name) |> String.downcase() == "metroninfo.xml",
              do: :metroninfo,
              else: :comicinfo

          case :zip.extract(path_charlist, [:memory, {:file_list, [name]}]) do
            {:ok, [{_name, data}]} -> {format, data}
            _ -> nil
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
      |> maybe_put(:genre, xpath(doc, ~x"//ComicInfo/Genre/text()"os))
      |> maybe_put(:tags, xpath(doc, ~x"//ComicInfo/Tags/text()"os))
      |> maybe_put(:story_arc, xpath(doc, ~x"//ComicInfo/StoryArc/text()"os))
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

      cover_year =
        case xpath(doc, ~x"//MetronInfo/CoverDate/text()"os) do
          nil -> nil
          "" -> nil
          date -> date |> String.slice(0, 4) |> parse_int()
        end

      store_year =
        case xpath(doc, ~x"//MetronInfo/StoreDate/text()"os) do
          nil -> nil
          "" -> nil
          date -> date |> String.slice(0, 4) |> parse_int()
        end

      genres =
        xpath(doc, ~x"//MetronInfo/Genres/Genre/text()"ls)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(", ")

      tags =
        xpath(doc, ~x"//MetronInfo/Tags/Tag/text()"ls)
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(", ")

      community_rating_raw = xpath(doc, ~x"//MetronInfo/CommunityRating/AverageRating/text()"os)
      community_rating =
        case community_rating_raw do
          nil -> nil
          "" -> nil
          s ->
            case Float.parse(s) do
              {f, _} -> f
              :error -> nil
            end
        end

      %{}
      |> maybe_put(:series, xpath(doc, ~x"//MetronInfo/Series/Name/text()"os))
      |> maybe_put(:volume, parse_int(xpath(doc, ~x"//MetronInfo/Series/Volume/text()"os)))
      |> maybe_put(:language, xpath(doc, ~x"//MetronInfo/Series/@lang"os))
      |> maybe_put(:issue_number, parse_decimal(xpath(doc, ~x"//MetronInfo/Number/text()"os)))
      |> maybe_put(:alternative_number, xpath(doc, ~x"//MetronInfo/AlternativeNumber/text()"os))
      |> maybe_put(:collection_title, xpath(doc, ~x"//MetronInfo/CollectionTitle/text()"os))
      |> maybe_put(:year, cover_year || store_year)
      |> maybe_put(:publisher, xpath(doc, ~x"//MetronInfo/Publisher/Name/text()"os))
      |> maybe_put(:page_count, parse_int(xpath(doc, ~x"//MetronInfo/PageCount/text()"os)))
      |> maybe_put(:summary, xpath(doc, ~x"//MetronInfo/Summary/text()"os))
      |> maybe_put(:age_rating, normalize_metroninfo_age_rating(age_rating_raw))
      |> maybe_put(:genre, if(genres != "", do: genres))
      |> maybe_put(:tags, if(tags != "", do: tags))
      |> maybe_put(:story_arc, xpath(doc, ~x"//MetronInfo/Arcs/Arc[1]/Name/text()"os))
      |> maybe_put(:community_rating, community_rating)
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
              nil -> nil
              date -> Regex.run(~r/(\d{4})/, date) |> then(fn
                [_, y] -> parse_int(y)
                _ -> nil
              end)
            end

          %{}
          |> maybe_put(:title, Map.get(fields, "Title"))
          |> maybe_put(:publisher, Map.get(fields, "Creator"))
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
      |> String.trim()

    result = %{}

    # "Issue 6 - Angel of Death (1996)" or "Volume 3 - Killing Angel"
    result =
      case Regex.run(~r/^(?:Issue|Vol(?:ume)?)\.?\s+(\d+)\s*(?:-|–)\s*(.+?)(?:\s*\((\d{4})\))?\s*$/i, clean) do
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

    # "Series Vol. NN (YEAR)" — e.g. Pariah Vol. 01 (2014)
    # Lookbehind prevents matching when dash immediately precedes "Vol." (handled by dash-Vol pattern below)
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)(?<![–\-])\s+Vol\.?\s+(\d{1,4}(?:\.\d+)?)\s+\((\d{4})\)/i, clean) do
          [_, series, volume, year] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
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
        case Regex.run(~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:-|–)\s*(?:Chapter|Ch\.?)\s+(\d{1,4})/i, clean) do
          [_, series, year, chapter] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(chapter))

          nil ->
            result
        end
      end

    # "Series (YEAR) - Issue N" or "Series (YEAR) - Issue N - Title"
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:-|–)\s*(?:Issue|Iss\.?)\s+(\d+(?:\.\d+)?)/i, clean) do
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

    result =
      if map_size(result) > 0 do
        result
      else
      case Regex.run(
             ~r/^(.+?)\s*\((\d{4})(?:-\d*)?\)\s*(?:v(\d+))?\s*(?:[#c]?(\d{1,4})(?:\.\d+)?)?/,
             clean
           ) do
        [_, series, year | rest] ->
          volume = Enum.at(rest, 0)
          issue = Enum.at(rest, 1)

          result
          |> Map.put(:series, String.trim(series))
          |> Map.put(:year, String.to_integer(year))
          |> maybe_put(:volume, parse_int(volume))
          |> maybe_put(:issue_number, parse_decimal(issue))

        nil ->
          case Regex.run(~r/^(.+?)\s+v(\d+)\s+(?:[#c]?(\d{1,4})(?:\.\d+)?)?/i, clean) do
            [_, series, volume | rest] ->
              issue = Enum.at(rest, 0)

              result
              |> Map.put(:series, String.trim(series))
              |> maybe_put(:volume, parse_int(volume))
              |> maybe_put(:issue_number, parse_decimal(issue))

            nil ->
              case Regex.run(~r/^(.+?)\s+[#c]?(\d{1,4})(?:\.\d+)?$/i, clean) do
                [_, series, issue] ->
                  result
                  |> Map.put(:series, String.trim(series))
                  |> maybe_put(:issue_number, parse_decimal(issue))

                nil ->
                  Map.put(result, :title, clean)
              end
          end
      end
      end

    result = maybe_put(result, :source_format, source_format)

    if not Map.has_key?(result, :title) do
      Map.put_new(result, :title, Map.get(result, :series, clean))
    else
      result
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

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
