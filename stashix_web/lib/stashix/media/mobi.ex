# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Mobi do
  @moduledoc """
  Reads the headers of Kindle books (`.mobi`, `.azw3`, `.azw`): metadata
  (EXTH records), the cover, whether the book is DRM-protected, and its
  length for progress.

  The text itself is never read here: foliate-js lays the book out in the
  browser from byte ranges of the file (`StashixWeb.BookFileController`).

  A Kindle book is a Palm database: a 78-byte header, a table of record
  offsets, then the records. Record 0 holds the PalmDOC header (compression,
  text length, encryption), the MOBI header and the EXTH metadata. Pictures
  are records too, from the MOBI header's first resource on. Only those
  bytes are read, and the result is kept in `Stashix.Media.PageCache`.
  KFX books (newer `.azw`) are not Palm databases and don't open.
  """

  alias Stashix.Media.PageCache

  # Bytes per foliate-js location, as `Stashix.Media.Epub` counts them.
  @chars_per_location 1500

  # EXTH record types (MobileRead wiki, "MOBI").
  @exth_author 100
  @exth_publisher 101
  @exth_description 103
  @exth_isbn 104
  @exth_subject 105
  @exth_date 106
  @exth_cover 201
  @exth_thumb 202
  @exth_title 503
  @exth_language 524

  @no_index 0xFFFFFFFF

  @type header :: %{
          encryption: non_neg_integer(),
          text_length: non_neg_integer(),
          title: String.t() | nil,
          first_resource: non_neg_integer() | nil,
          offsets: [non_neg_integer()],
          size: non_neg_integer(),
          exth: %{non_neg_integer() => [binary()]}
        }

  @doc "The book's headers, or `{:error, :not_mobi}` for anything else."
  @spec header(Path.t()) :: {:ok, header()} | {:error, term()}
  def header(path), do: PageCache.fetch(path, :mobi_header, fn -> read_header(path) end)

  @doc "Whether the book is encrypted (DRM): it can't be opened then."
  @spec drm?(Path.t()) :: boolean()
  def drm?(path), do: match?({:ok, %{encryption: e}} when e != 0, header(path))

  @doc "Estimated length in reader locations, from the uncompressed text length."
  @spec location_count(Path.t()) :: non_neg_integer()
  def location_count(path) do
    case header(path) do
      {:ok, %{text_length: n}} -> ceil(n / @chars_per_location)
      _ -> 0
    end
  end

  @doc """
  Metadata in the shape `Stashix.Metadata.Parser` returns: title, credits
  (authors as writers), publisher, summary, year, cover date, language, ISBN
  and subjects as genres.
  """
  @spec metadata(Path.t()) :: map()
  def metadata(path) do
    case header(path) do
      {:ok, %{exth: exth} = h} ->
        one = fn type -> exth |> Map.get(type, []) |> List.first() |> clean() end
        date = parse_date(one.(@exth_date))

        %{}
        |> put(:title, one.(@exth_title) || clean(h.title))
        |> put(:credits, credits(Map.get(exth, @exth_author, [])))
        |> put(:publisher, one.(@exth_publisher))
        |> put(:summary, one.(@exth_description) |> strip_html())
        |> put(:year, date && date.year)
        |> put(:cover_date, date)
        |> put(:language, language(one.(@exth_language)))
        |> put(:isbn, one.(@exth_isbn))
        |> put(:genres, exth |> Map.get(@exth_subject, []) |> Enum.map(&clean/1) |> Enum.reject(&is_nil/1))

      _ ->
        %{}
    end
  end

  @doc "The cover picture's bytes (EXTH cover, else thumbnail record)."
  @spec cover(Path.t()) :: {:ok, binary()} | {:error, term()}
  def cover(path) do
    with {:ok, %{first_resource: first} = h} when is_integer(first) <- header(path),
         index when is_integer(index) <- cover_index(h.exth),
         {:ok, data} <- read_record(path, h, first + index),
         true <- image?(data) do
      {:ok, data}
    else
      {:error, _} = error -> error
      _ -> {:error, :no_cover}
    end
  end

  defp cover_index(exth) do
    Enum.find_value([@exth_cover, @exth_thumb], fn type ->
      case exth[type] do
        [<<n::32>> | _] when n != @no_index -> n
        _ -> nil
      end
    end)
  end

  defp image?(<<0xFF, 0xD8, _::binary>>), do: true
  defp image?(<<0x89, "PNG", _::binary>>), do: true
  defp image?(<<"GIF8", _::binary>>), do: true
  defp image?(_), do: false

  ## Reading

  defp read_header(path) do
    with {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        with {:ok, %File.Stat{size: size}} <- File.stat(path),
             {:ok, <<_name::binary-32, _::binary-28, "BOOK", "MOBI", _::binary-8, count::16>>} <-
               pread(file, 0, 78),
             {:ok, table} <- pread(file, 78, count * 8),
             offsets = for(<<offset::32, _attrs::32 <- table>>, do: offset),
             [first, second | _] <- offsets,
             {:ok, record0} <- pread(file, first, second - first) do
          parse_record0(record0, offsets, size)
        else
          _ -> {:error, :not_mobi}
        end
      after
        File.close(file)
      end
    end
  end

  defp pread(file, at, len) do
    case :file.pread(file, at, len) do
      {:ok, data} when byte_size(data) == len -> {:ok, data}
      _ -> {:error, :short_read}
    end
  end

  defp parse_record0(
         <<_compression::16, _::16, text_length::32, _records::16, _size::16, encryption::16, _::16, "MOBI",
           header_length::32, _type::32, encoding::32, _::binary>> = record0,
         offsets,
         size
       ) do
    field = fn at -> u32(record0, at) end

    {:ok,
     %{
       encryption: encryption,
       text_length: text_length,
       title: name(record0, field.(84), field.(88), encoding),
       first_resource: if(field.(108) not in [nil, @no_index], do: field.(108)),
       offsets: offsets,
       size: size,
       exth: if(Bitwise.band(field.(128) || 0, 0x40) != 0, do: exth(record0, 16 + header_length, encoding), else: %{})
     }}
  end

  defp parse_record0(_record0, _offsets, _size), do: {:error, :not_mobi}

  defp u32(bin, at) when byte_size(bin) >= at + 4, do: :binary.decode_unsigned(binary_part(bin, at, 4))
  defp u32(_bin, _at), do: nil

  defp name(record0, at, len, encoding) when is_integer(at) and is_integer(len) and at + len <= byte_size(record0),
    do: decode(binary_part(record0, at, len), encoding)

  defp name(_record0, _at, _len, _encoding), do: nil

  # Records are {type, data}; a type may repeat (several authors).
  defp exth(record0, at, encoding) do
    case record0 do
      <<_::binary-size(^at), "EXTH", _length::32, count::32, rest::binary>> ->
        rest
        |> exth_records(count, [])
        |> Enum.group_by(&elem(&1, 0), fn {type, data} ->
          if type in [@exth_cover, @exth_thumb], do: data, else: decode(data, encoding)
        end)

      _ ->
        %{}
    end
  end

  defp exth_records(_rest, 0, acc), do: Enum.reverse(acc)

  defp exth_records(<<type::32, length::32, rest::binary>>, count, acc)
       when length >= 8 and byte_size(rest) >= length - 8 do
    data = binary_part(rest, 0, length - 8)
    rest = binary_part(rest, length - 8, byte_size(rest) - length + 8)
    exth_records(rest, count - 1, [{type, data} | acc])
  end

  defp exth_records(_rest, _count, acc), do: Enum.reverse(acc)

  defp read_record(path, %{offsets: offsets, size: size}, index) do
    with start when is_integer(start) <- Enum.at(offsets, index),
         stop = Enum.at(offsets, index + 1, size),
         true <- stop > start,
         {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        pread(file, start, stop - start)
      after
        File.close(file)
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :no_record}
    end
  end

  ## Values

  # 65001 is UTF-8; older books are CP1252, read here as Latin-1.
  defp decode(data, 65_001), do: if(String.valid?(data), do: data, else: latin1(data))
  defp decode(data, _encoding), do: latin1(data)

  defp latin1(data), do: :unicode.characters_to_binary(data, :latin1)

  defp clean(nil), do: nil

  defp clean(s) do
    case s |> String.replace(<<0>>, "") |> String.trim() do
      "" -> nil
      s -> s
    end
  end

  defp strip_html(nil), do: nil

  defp strip_html(html) do
    case Floki.parse_fragment(html) do
      {:ok, nodes} -> nodes |> Floki.text(sep: " ") |> String.replace(~r/\s+/u, " ") |> clean()
      _ -> html
    end
  end

  # "Last, First" stays as the book has it; "A & B" / "A; B" are two people.
  defp credits(authors) do
    authors
    |> Enum.flat_map(&String.split(&1, ~r/\s*(?:;|&|\band\b)\s*/))
    |> Enum.map(&clean/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&%{creator: &1, roles: ["Writer"]})
  end

  # "2011-09-13T07:00:00+00:00", "2011-09-13", "2011".
  defp parse_date(nil), do: nil

  defp parse_date(s) do
    case Regex.run(~r/^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?/, s) do
      [_, y | rest] ->
        [m, d] = (rest ++ [nil, nil]) |> Enum.take(2) |> Enum.map(&(&1 && String.to_integer(&1)))

        case Date.new(String.to_integer(y), m || 1, d || 1) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # "en-US" → "en", as LanguageISO has it.
  defp language(nil), do: nil
  defp language(tag), do: tag |> String.split(["-", "_"]) |> hd() |> String.downcase()

  defp put(map, _key, nil), do: map
  defp put(map, _key, []), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
