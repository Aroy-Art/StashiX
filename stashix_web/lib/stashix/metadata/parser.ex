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

    xml =
      case ext do
        cbz when cbz in [".cbz", ".epub"] -> extract_xml_from_zip(archive_path)
        _ -> nil
      end

    case xml do
      nil -> %{}
      data -> parse_comicinfo_xml(data)
    end
  end

  defp extract_xml_from_zip(archive_path) do
    path_charlist = String.to_charlist(archive_path)

    with {:ok, entries} <- :zip.list_dir(path_charlist) do
      xml_entry =
        entries
        |> Enum.find(fn
          {:zip_file, name, _info, _comment, _offset, _comp_size} ->
            n = to_string(name) |> String.downcase()
            n == "comicinfo.xml" || n == "metroninfo.xml"

          _ ->
            false
        end)

      case xml_entry do
        nil ->
          nil

        {:zip_file, name, _info, _comment, _offset, _comp_size} ->
          case :zip.extract(path_charlist, [:memory, {:file_list, [name]}]) do
            {:ok, [{_name, data}]} -> data
            _ -> nil
          end
      end
    else
      _ -> nil
    end
  end

  defp parse_comicinfo_xml(data) when is_binary(data) do
    try do
      doc = parse(data)

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
    end
  end

  def parse_filename(filename) do
    clean = Regex.replace(@noise_regex, filename, " ") |> String.trim()

    result = %{}

    # "Issue 6 - Angel of Death (1996)" or "Volume 3 - Killing Angel"
    result =
      case Regex.run(~r/^(?:Issue|Vol(?:ume)?)\.?\s+(\d+)\s*[-–]\s*(.+?)(?:\s*\((\d{4})\))?\s*$/i, clean) do
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

    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(~r/^(.+?)\s*\((\d{4})(?:-\d{4})?\)\s*[-–]\s*(?:Chapter|Ch\.?)\s+(\d{1,4})/i, clean) do
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
        case Regex.run(~r/^(.+?)\s*\((\d{4})(?:-\d{4})?\)\s*[-–]\s*(?:Issue|Iss\.?)\s+(\d+(?:\.\d+)?)/i, clean) do
          [_, series, year, issue] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:year, String.to_integer(year))
            |> Map.put(:issue_number, parse_decimal(issue))

          nil ->
            result
        end
      end

    result =
      if map_size(result) > 0 do
        result
      else
      case Regex.run(
             ~r/^(.+?)\s*\((\d{4})(?:-\d{4})?\)\s*(?:v(\d+))?\s*(?:[#c]?(\d{1,4})(?:\.\d+)?)?/,
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
