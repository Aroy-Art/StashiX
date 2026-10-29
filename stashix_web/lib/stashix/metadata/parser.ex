# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Parser do
  @moduledoc """
  Reads metadata for a library file: embedded/sidecar XML (via
  `Stashix.Metadata.Format.MetronInfo` / `Stashix.Metadata.Format.ComicInfo`),
  PDF info, and the file name.

  Precedence inside `parse_comicinfo/1`, highest first (see
  docs/metadata-file-io.md):

    1. `<book name>.xml` sidecar next to the file
    2. embedded `MetronInfo.xml`
    3. embedded `ComicInfo.xml` (or the PDF info dict for `.pdf`)

  Exception: ComicInfo's `Year` beats the year MetronInfo derives from its
  dates, because MetronInfo has no Year element of its own.
  """

  alias Stashix.Metadata.Format.{ComicInfo, MetronInfo}

  @noise_patterns ~w(
    Digital Webrip c2c HQ Retail
    HD 1080p 720p 480p
    FIXED Corrected v2 v3
    f2 f3
    DCP [A-Za-z0-9]+-DCP
  )

  @noise_regex Regex.compile!(
                 "\\s*\\((?:#{Enum.join(@noise_patterns, "|")})\\)\\s*",
                 "i"
               )

  def parse_comicinfo(archive_path) do
    case parse_sidecar(archive_path) do
      nil -> parse_embedded(archive_path)
      sidecar -> merge_records(parse_embedded(archive_path), sidecar)
    end
  end

  # Right side wins field-by-field, but external ids are unioned per source so
  # e.g. a Comic Vine id only present in ComicInfo survives next to MetronInfo's.
  defp merge_records(base, override) do
    ids =
      (List.wrap(override[:external_ids]) ++ List.wrap(base[:external_ids]))
      |> Enum.uniq_by(& &1.source)

    base
    |> Map.merge(override)
    |> maybe_put(:external_ids, if(ids != [], do: ids))
  end

  # A `<book name>.xml` next to the file (written by metadata write-back for
  # formats we can't embed into) takes precedence over embedded data.
  defp parse_sidecar(archive_path) do
    path = Path.rootname(archive_path) <> ".xml"

    with true <- File.regular?(path),
         {:ok, data} <- File.read(path) do
      cond do
        String.contains?(data, "<MetronInfo") -> parse_xml(MetronInfo, data)
        String.contains?(data, "<ComicInfo") -> parse_xml(ComicInfo, data)
        true -> nil
      end
    else
      _ -> nil
    end
  end

  defp parse_embedded(archive_path) do
    case archive_path |> Path.extname() |> String.downcase() do
      ext when ext in [".cbz", ".epub"] ->
        case extract_xml_from_zip(archive_path) do
          nil -> %{}
          xmls -> merge_embedded(xmls)
        end

      ".pdf" ->
        parse_pdf_metadata(archive_path)

      _ ->
        %{}
    end
  end

  defp merge_embedded(xmls) do
    comic = if data = xmls[:comicinfo], do: parse_xml(ComicInfo, data), else: %{}
    metron = if data = xmls[:metroninfo], do: parse_xml(MetronInfo, data), else: %{}

    # When MetronInfo is present it owns the title — don't let ComicInfo's
    # title bleed through even if MetronInfo has no stories element.
    comic = if xmls[:metroninfo], do: Map.delete(comic, :title), else: comic

    comic
    |> merge_records(metron)
    |> maybe_put(:year, comic[:year])
  end

  defp parse_xml(format, data) do
    case format.parse(data) do
      {:ok, record} -> record
      {:error, _} -> %{}
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
      # Whatever trails the year is scanner/release tagging — "(1994)(FB-DCP)(Group)"
      |> then(&Regex.replace(~r/(\(\d{4}\))(?:\s*\([^)]*\))+\s*$/, &1, "\\1"))
      # "Series 021(1994)" — give the issue number room before its paren group
      |> then(&Regex.replace(~r/(\d)\(/, &1, "\\1 ("))
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

    # "Series - Title - Issue N" — e.g. "Ghost in the Shell 1.5 - Human Error Processor - Issue 02".
    # An explicit trailing "Issue N" beats a number embedded in the series name.
    result =
      if map_size(result) > 0 do
        result
      else
        case Regex.run(
               ~r/^(.+?)\s*(?:-|–)\s*(?:(.+?)\s*(?:-|–)\s*)?(?:Issue|Iss\.?)\s+(\d+(?:\.\d+)?)(?:\s*\((\d{4})\))?\s*$/i,
               clean
             ) do
          [_, series, title, issue | rest] ->
            result
            |> Map.put(:series, String.trim(series))
            |> Map.put(:issue_number, parse_decimal(issue))
            |> then(&if(title != "", do: Map.put(&1, :title, String.trim(title)), else: &1))
            |> maybe_put(:year, parse_int(Enum.at(rest, 0)))

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
    # Yearless paren groups are story-arc or scanner tags — e.g.
    # "Dark Horse Comics 008 (Coyote)" — and would hide a trailing issue number.
    stripped = Regex.replace(~r/\s*\((?![^)]*\d{4})[^)]*\)/, clean, "") |> String.trim()

    with nil <- match_year_pattern(result, stripped),
         nil <- match_volume_pattern(result, stripped),
         nil <- match_issue_pattern(result, stripped) do
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

  # Old ComicVine/ComicTagger tools stored the series start year in <Volume>.
  # A 4-digit year-shaped value is not a real volume number.
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc "See `Stashix.Metadata.Format.ComicInfo.external_ids/2`."
  defdelegate external_ids_from_comicinfo(urls, notes), to: ComicInfo, as: :external_ids

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
end
