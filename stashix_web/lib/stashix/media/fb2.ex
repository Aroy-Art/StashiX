# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Fb2 do
  @moduledoc """
  Reads FictionBook books: `.fb2` (one XML file) and `.fbz` / `.fb2.zip`
  (that file zipped). foliate-js lays the book out in the browser from the
  XML (`StashixWeb.BookFileController` unzips it first); here only the
  `<description>` is read for metadata, and the cover picture, which FB2
  carries base64-encoded in a `<binary>` element.

  FB2 files are small (rarely over a few MB) and read whole.
  """

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  alias Stashix.Media.{Archive, Formats, PageCache}
  alias Stashix.Metadata.Format.XML

  @chars_per_location 1500

  @doc "The book's XML, unzipped when it comes zipped."
  @spec read(Path.t()) :: {:ok, binary()} | {:error, term()}
  def read(path) do
    case Formats.format(path) do
      :fbz -> read_zipped(path)
      _ -> File.read(path)
    end
  end

  defp read_zipped(path) do
    with {:ok, names} <- Archive.list(path),
         name when is_binary(name) <-
           Enum.find(names, &String.ends_with?(String.downcase(&1), ".fb2")) || List.first(names) do
      Archive.read(path, name)
    else
      {:error, _} = error -> error
      _ -> {:error, :empty}
    end
  end

  @doc """
  Metadata in the shape `Stashix.Metadata.Parser` returns: title, authors
  (writers) and translators, series (`<sequence>`) and number, summary
  (`<annotation>`), genres, language, year, publisher and ISBN.
  """
  @spec metadata(Path.t()) :: map()
  def metadata(path) do
    case description(path) do
      {:ok, doc} -> parse_description(doc)
      _ -> %{}
    end
  end

  defp description(path) do
    PageCache.fetch(path, :fb2_description, fn ->
      with {:ok, xml} <- read(path),
           [desc] <- Regex.run(~r{<description\b.*?</description>}s, xml) do
        XML.parse_document(utf8(desc, encoding(xml)))
      else
        {:error, _} = error -> error
        _ -> {:error, :no_description}
      end
    end)
  end

  defp parse_description(doc) do
    title = ~x"//*[local-name()='title-info']"
    publish = ~x"//*[local-name()='publish-info']"
    text = fn node, path -> node |> xpath(path) |> clean() end
    info = xpath(doc, title)
    pub = xpath(doc, publish)

    {series, number} =
      case info && xpath(info, ~x"./*[local-name()='sequence'][1]") do
        nil -> {nil, nil}
        seq -> {seq |> xpath(~x"./@name"s) |> clean(), xpath(seq, ~x"./@number"s)}
      end

    year =
      info &&
        year(text.(info, ~x"./*[local-name()='date']/@value"s) || text.(info, ~x"./*[local-name()='date']/text()"s))

    year = year || (pub && year(text.(pub, ~x"./*[local-name()='year']/text()"s)))

    if info do
      %{}
      |> put(:title, text.(info, ~x"./*[local-name()='book-title']/text()"s))
      |> put(:credits, credits(info))
      |> put(:series, series)
      |> put(:issue_number, series && decimal(number))
      |> put(:summary, info |> xpath(~x"./*[local-name()='annotation']//text()"ls) |> Enum.join(" ") |> squash())
      |> put(
        :genres,
        info |> xpath(~x"./*[local-name()='genre']/text()"ls) |> Enum.map(&clean/1) |> Enum.reject(&is_nil/1)
      )
      |> put(:language, text.(info, ~x"./*[local-name()='lang']/text()"s))
      |> put(:year, year)
      |> put(:publisher, pub && text.(pub, ~x"./*[local-name()='publisher']/text()"s))
      |> put(:isbn, pub && pub |> text.(~x"./*[local-name()='isbn']/text()"s) |> isbn())
    else
      %{}
    end
  end

  defp credits(info) do
    people = fn tag ->
      info
      |> xpath(~x"./*[local-name()='#{tag}']"l,
        first: ~x"./*[local-name()='first-name']/text()"s,
        middle: ~x"./*[local-name()='middle-name']/text()"s,
        last: ~x"./*[local-name()='last-name']/text()"s,
        nick: ~x"./*[local-name()='nickname']/text()"s
      )
      |> Enum.map(fn p ->
        case [p.first, p.middle, p.last] |> Enum.map(&clean/1) |> Enum.reject(&is_nil/1) do
          [] -> clean(p.nick)
          parts -> Enum.join(parts, " ")
        end
      end)
      |> Enum.reject(&is_nil/1)
    end

    (Enum.map(people.("author"), &{&1, "Writer"}) ++ Enum.map(people.("translator"), &{&1, "Translator"}))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {creator, roles} -> %{creator: creator, roles: Enum.uniq(roles)} end)
    |> Enum.sort_by(& &1.creator)
  end

  @doc "The cover picture's bytes: the `<binary>` the `<coverpage>` points at."
  @spec cover(Path.t()) :: {:ok, binary()} | {:error, term()}
  def cover(path) do
    with {:ok, xml} <- read(path),
         [_, id] <- Regex.run(~r{<coverpage\b.*?<[\w:]*image\b[^>]*?href\s*=\s*["']#([^"']+)["']}s, xml),
         [_, data] <- Regex.run(~r{<binary\b[^>]*\bid\s*=\s*["']#{Regex.escape(id)}["'][^>]*>(.*?)</binary>}s, xml),
         {:ok, bytes} <- Base.decode64(String.replace(data, ~r/\s+/, "")) do
      {:ok, bytes}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_cover}
    end
  end

  @doc "Estimated length in reader locations: the text, without its pictures."
  @spec location_count(Path.t()) :: non_neg_integer()
  def location_count(path) do
    case read(path) do
      {:ok, xml} ->
        text = Regex.replace(~r{<binary\b.*?</binary>}s, xml, "")
        ceil(byte_size(text) / @chars_per_location)

      _ ->
        0
    end
  end

  ## Values

  defp encoding(xml) do
    case Regex.run(~r/\A(?:\xEF\xBB\xBF)?<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']/i, xml) do
      [_, enc] -> String.downcase(enc)
      _ -> "utf-8"
    end
  end

  # The description is parsed on its own, as UTF-8. Older Russian FB2s are
  # windows-1251, which Erlang can't decode: those keep what is ASCII.
  defp utf8(desc, enc) when enc in ["utf-8", "utf8"], do: desc

  defp utf8(desc, enc) when enc in ["iso-8859-1", "latin1", "windows-1252"],
    do: :unicode.characters_to_binary(desc, :latin1)

  defp utf8(desc, _enc), do: if(String.valid?(desc), do: desc, else: for(<<c <- desc>>, c < 128, into: "", do: <<c>>))

  defp clean(nil), do: nil

  defp clean(s) do
    case String.trim(s) do
      "" -> nil
      s -> s
    end
  end

  defp squash(s), do: s |> String.replace(~r/\s+/u, " ") |> clean()

  defp year(nil), do: nil

  defp year(s) do
    case Regex.run(~r/\b(\d{4})\b/, s) do
      [_, y] -> String.to_integer(y)
      _ -> nil
    end
  end

  defp decimal(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp isbn(nil), do: nil

  defp isbn(s) do
    case String.replace(s, ~r/[^0-9Xx]/, "") do
      digits when byte_size(digits) in [10, 13] -> String.upcase(digits)
      _ -> nil
    end
  end

  defp put(map, _key, nil), do: map
  defp put(map, _key, ""), do: map
  defp put(map, _key, []), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
