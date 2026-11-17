# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Extractor do
  alias Stashix.Media.{Archive, Epub, PageCache, RenderCache}

  @image_exts ~w(.jpg .jpeg .png .gif .webp)

  # Known credit/ad pages that don't follow the z-prefix convention (lowercase, no extension).
  @credit_page_names ["the saint", "coverbrazoff", "zsou-nerd"]

  # Exclude scanner/group credit pages — e.g. "zSoU-Nerd.jpg".
  # These are sorted last by prefixing 'z' and contain no page numbers.
  defp z_prefixed?(name), do: String.match?(page_basename(name), ~r/^z[^0-9]/i)

  defp known_credit_page?(name), do: String.downcase(page_basename(name)) in @credit_page_names

  defp page_basename(name), do: name |> Path.basename() |> Path.rootname()

  # Credit pages are a few files at the end of a book. When most of the pages are
  # z-prefixed the book is simply named that way ("Zatanna 001.jpg"), so keep them.
  defp reject_credit_pages(names) do
    names = Enum.reject(names, &known_credit_page?/1)
    {z_pages, rest} = Enum.split_with(names, &z_prefixed?/1)

    if length(z_pages) > length(rest), do: names, else: rest
  end

  # The extension only says "archive"; `Archive` picks zip/RAR/7z by content,
  # so a zip named .cbr (or a RAR named .cbz) still opens.
  @archive_exts ~w(.cbz .cbr .cb7 .epub)

  def list_pages(book_path) do
    case book_path |> Path.extname() |> String.downcase() do
      ".pdf" -> list_pdf_pages(book_path)
      ".epub" -> list_epub_pages(book_path)
      ext when ext in @archive_exts -> list_archive_pages(book_path)
      _ -> {:error, :unsupported_format}
    end
  end

  @doc """
  Like `list_pages/1`, but remembered per file (see `PageCache`). For serving
  pages; checks that must read the file itself (scanner, integrity) use
  `list_pages/1`.
  """
  def cached_pages(book_path), do: PageCache.fetch(book_path, fn -> list_pages(book_path) end)

  # Rendered PDF page widths. A requested width rounds up to one of these, so
  # the render cache holds a few sizes per page rather than one per screen.
  @pdf_widths [480, 800, 1200, 1600, 2400]

  @doc "Widths a PDF page can be rendered at (see `get_page/3`)."
  def pdf_widths, do: @pdf_widths

  @doc """
  The page at `page_index`. `width:` renders PDF pages to that width (rounded
  up to one of `pdf_widths/0`, cached on disk); without it they render at
  150 dpi. Archive pages are always the stored image.
  """
  def get_page(book_path, page_index, opts \\ []) do
    case cached_pages(book_path) do
      {:ok, pages} ->
        page_name = Enum.at(pages, page_index)

        if page_name do
          extract_page(book_path, page_name, opts[:width])
        else
          {:error, :page_not_found}
        end

      error ->
        error
    end
  end

  def get_page_count(book_path) do
    case list_pages(book_path) do
      {:ok, pages} -> length(pages)
      _ -> 0
    end
  end

  defp list_archive_pages(path) do
    with {:ok, names} <- Archive.list(path) do
      pages =
        names
        |> Enum.filter(&(String.downcase(Path.extname(&1)) in @image_exts))
        |> reject_credit_pages()
        |> Enum.sort()

      {:ok, pages}
    end
  end

  # An image EPUB's pages come in spine order. Without one (text, or a
  # package that can't be read) its images are listed like a comic's, which
  # at least shows a text book's cover.
  defp list_epub_pages(path) do
    case Epub.pages(path) do
      nil -> list_archive_pages(path)
      pages -> {:ok, pages}
    end
  end

  defp list_pdf_pages(path) do
    try do
      case System.cmd("pdfinfo", [path], stderr_to_stdout: true) do
        {output, 0} ->
          pages =
            output
            |> String.split("\n", trim: true)
            |> Enum.find_value(fn line ->
              case Regex.run(~r/^Pages:\s+(\d+)/, line) do
                [_, n] -> String.to_integer(n)
                _ -> nil
              end
            end) || 0

          page_names =
            Enum.map(1..max(pages, 1), &"page-#{String.pad_leading(to_string(&1), 4, "0")}.jpg")

          {:ok, page_names}

        {error, _} ->
          {:error, error}
      end
    rescue
      ErlangError -> {:error, :pdfinfo_not_found}
    end
  end

  defp extract_page(book_path, page_name, width) do
    case book_path |> Path.extname() |> String.downcase() do
      ".pdf" -> extract_pdf_page(book_path, page_name, width)
      ext when ext in @archive_exts -> extract_archive_page(book_path, page_name)
      _ -> {:error, :unsupported_format}
    end
  end

  defp extract_archive_page(path, name) do
    case Archive.read(path, name) do
      {:error, :not_found} -> {:error, :page_not_found}
      other -> other
    end
  end

  defp extract_pdf_page(path, page_name, width) do
    page_num =
      case Regex.run(~r/page-(\d+)/, page_name) do
        [_, n] -> String.to_integer(n)
        _ -> 1
      end

    case pdf_width(width) do
      nil ->
        render_pdf_page(path, page_num, ["-r", "150"])

      w ->
        RenderCache.fetch(path, "p#{page_num}-w#{w}", fn ->
          render_pdf_page(path, page_num, ["-scale-to-x", to_string(w), "-scale-to-y", "-1"])
        end)
    end
  end

  defp pdf_width(w) when is_integer(w) and w > 0, do: Enum.find(@pdf_widths, List.last(@pdf_widths), &(&1 >= w))
  defp pdf_width(_), do: nil

  # No output root: pdftoppm writes the one page to stdout. Empty output
  # means the page is out of range (pdftoppm exits non-zero then too).
  defp render_pdf_page(path, page_num, size_args) do
    args = ["-jpeg"] ++ size_args ++ ["-f", to_string(page_num), "-l", to_string(page_num), "--", path]

    case System.cmd("pdftoppm", args, stderr_to_stdout: false) do
      {"", _} -> {:error, :page_not_found}
      {data, 0} -> {:ok, data}
      {_, status} -> {:error, {"pdftoppm", status}}
    end
  rescue
    ErlangError -> {:error, :pdftoppm_not_found}
  end
end
