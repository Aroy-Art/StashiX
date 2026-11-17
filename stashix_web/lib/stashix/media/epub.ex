# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Epub do
  @moduledoc """
  Reads EPUB files: single entries for the text reader, the package (OPF)
  for its reading order, and from that whether the book is text or page
  images and, for the latter, its pages in order.

  The zip's central directory and the parsed package are kept in
  `Stashix.Media.PageCache`, so serving an entry is a seek and a read rather
  than a re-list. Zip64 files (over 4 GB) are not read this way and fall back
  to `Stashix.Media.Archive`.
  """

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  alias Stashix.Media.{Archive, PageCache}
  alias Stashix.Metadata.Format.XML

  # Sizes per foliate-js location, the reader's unit of progress; the
  # scanner's estimate of a text book's length uses the same.
  @chars_per_location 1500

  @type item :: %{id: String.t(), href: String.t(), media_type: String.t(), properties: [String.t()]}
  @type package :: %{
          opf: String.t(),
          layout: String.t() | nil,
          manifest: %{String.t() => item()},
          spine: [%{item: item(), linear: boolean()}]
        }

  @doc "Entry names with their uncompressed sizes."
  @spec entries(Path.t()) :: {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  def entries(path) do
    with {:ok, unzip} <- directory(path) do
      {:ok, Map.new(Unzip.list_entries(unzip), &{&1.file_name, &1.uncompressed_size})}
    end
  end

  @doc "One entry's contents. `{:error, :not_found}` for a name not in the zip."
  @spec read(Path.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(path, name) do
    case directory(path) do
      {:ok, unzip} ->
        read_entry(unzip, path, name)

      {:error, _} ->
        Archive.read(path, name)
    end
  end

  # The cached directory comes without a file handle (handles belong to the
  # process that opened them); each read opens the file for itself.
  defp read_entry(unzip, path, name) do
    file = Unzip.LocalFile.open(path)

    try do
      {:ok, %{unzip | zip: file} |> Unzip.file_stream!(name) |> Enum.into([]) |> IO.iodata_to_binary()}
    rescue
      # Raised for a name that is not in the zip, before anything is read.
      Unzip.Error -> {:error, :not_found}
      e -> {:error, e}
    after
      Unzip.LocalFile.close(file)
    end
  end

  defp directory(path) do
    PageCache.fetch(path, :epub_directory, fn ->
      file = Unzip.LocalFile.open(path)

      try do
        with {:ok, unzip} <- Unzip.new(file), do: {:ok, %{unzip | zip: nil}}
      rescue
        e -> {:error, e}
      after
        Unzip.LocalFile.close(file)
      end
    end)
  rescue
    # LocalFile.open matches on {:ok, _}: an unreadable file raises.
    e in MatchError -> {:error, e}
  end

  @doc "The parsed package: manifest, spine and rendition layout."
  @spec package(Path.t()) :: {:ok, package()} | {:error, term()}
  def package(path) do
    PageCache.fetch(path, :epub_package, fn ->
      with {:ok, container} <- read(path, "META-INF/container.xml"),
           {:ok, doc} <- XML.parse_document(container),
           opf when is_binary(opf) and opf != "" <-
             xpath(doc, ~x"//*[local-name()='rootfile'][1]/@full-path"s) |> blank_to_nil(),
           {:ok, data} <- read(path, opf),
           {:ok, doc} <- XML.parse_document(data) do
        {:ok, parse_package(doc, opf)}
      else
        {:error, _} = error -> error
        _ -> {:error, :no_package}
      end
    end)
  end

  defp parse_package(doc, opf) do
    base = Path.dirname(opf)

    manifest =
      doc
      |> xpath(~x"//*[local-name()='manifest']/*[local-name()='item']"l,
        id: ~x"./@id"s,
        href: ~x"./@href"s,
        media_type: ~x"./@media-type"s,
        properties: ~x"./@properties"s
      )
      |> Map.new(fn item ->
        {item.id,
         %{item | href: resolve(base, item.href), properties: String.split(item.properties, ~r/\s+/, trim: true)}}
      end)

    spine =
      doc
      |> xpath(~x"//*[local-name()='spine']/*[local-name()='itemref']"l, idref: ~x"./@idref"s, linear: ~x"./@linear"s)
      |> Enum.flat_map(fn ref ->
        case manifest[ref.idref] do
          nil -> []
          item -> [%{item: item, linear: ref.linear != "no"}]
        end
      end)

    layout =
      xpath(doc, ~x"//*[local-name()='meta'][@property='rendition:layout']/text()"s) |> blank_to_nil() ||
        xpath(doc, ~x"//*[local-name()='meta'][@name='fixed-layout']/@content"s)
        |> then(&if(&1 == "true", do: "pre-paginated"))

    %{opf: opf, layout: layout, manifest: manifest, spine: spine}
  end

  @doc """
  `:images` for a fixed-layout book, or one whose every spine document only
  wraps a picture; `:text` otherwise; `nil` when it can't be read.
  """
  @spec content_kind(Path.t()) :: :images | :text | nil
  def content_kind(path) do
    case package(path) do
      {:ok, %{layout: "pre-paginated"}} -> :images
      {:ok, %{spine: []}} -> nil
      {:ok, package} -> if image_pages(path, package) != nil, do: :images, else: :text
      {:error, _} -> nil
    end
  end

  @doc """
  The page images of an image book in reading order: each spine item's
  picture. `nil` when some spine document carries text of its own.
  """
  @spec pages(Path.t()) :: [String.t()] | nil
  def pages(path) do
    case package(path) do
      {:ok, package} -> image_pages(path, package)
      _ -> nil
    end
  end

  # Spine documents with more than this much text are prose, not a page.
  @max_page_text 200

  defp image_pages(path, %{spine: spine}) do
    pages =
      Enum.reduce_while(spine, [], fn %{item: item}, acc ->
        case spine_image(path, item) do
          {:image, href} -> {:cont, [href | acc]}
          :blank -> {:cont, acc}
          :text -> {:halt, :text}
        end
      end)

    case pages do
      list when is_list(list) and list != [] -> Enum.reverse(list)
      _ -> nil
    end
  end

  defp spine_image(_path, %{media_type: "image/" <> _, href: href}), do: {:image, href}

  defp spine_image(path, %{href: href}) do
    with {:ok, html} <- read(path, href),
         {:ok, doc} <- Floki.parse_document(html) do
      text = doc |> Floki.find("body") |> Floki.text() |> String.replace(~r/\s+/u, "")
      src = image_src(doc)

      cond do
        String.length(text) > @max_page_text -> :text
        src -> {:image, resolve(Path.dirname(href), src)}
        true -> :blank
      end
    else
      _ -> :text
    end
  end

  defp image_src(doc) do
    doc |> Floki.attribute("img", "src") |> List.first() ||
      doc |> Floki.attribute("image", "xlink:href") |> List.first() ||
      doc |> Floki.attribute("image", "href") |> List.first()
  end

  @doc """
  Estimated length in reader locations (about #{@chars_per_location} bytes of
  linear content each), so text books get a page count progress can use.
  """
  @spec location_count(Path.t()) :: non_neg_integer()
  def location_count(path) do
    with {:ok, %{spine: spine}} <- package(path),
         {:ok, sizes} <- entries(path) do
      total = for %{item: item, linear: true} <- spine, reduce: 0, do: (acc -> acc + Map.get(sizes, item.href, 0))
      ceil(total / @chars_per_location)
    else
      _ -> 0
    end
  end

  # Zip names are relative to the archive root; hrefs to the document they
  # are in, percent-encoded, maybe with a fragment.
  defp resolve(base, href) do
    href = href |> String.split("#", parts: 2) |> hd() |> URI.decode()

    [base, href]
    |> Path.join()
    |> Path.split()
    |> Enum.reduce([], fn
      ".", acc -> acc
      "..", acc -> Enum.drop(acc, 1)
      part, acc -> [part | acc]
    end)
    |> Enum.reverse()
    |> Enum.join("/")
  end

  defp blank_to_nil(s), do: XML.blank_to_nil(s)
end
