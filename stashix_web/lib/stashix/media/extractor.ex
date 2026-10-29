# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Extractor do
  alias Stashix.Media.Archive

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
      ext when ext in @archive_exts -> list_archive_pages(book_path)
      _ -> {:error, :unsupported_format}
    end
  end

  def get_page(book_path, page_index) do
    case list_pages(book_path) do
      {:ok, pages} ->
        page_name = Enum.at(pages, page_index)

        if page_name do
          extract_page(book_path, page_name)
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

  defp extract_page(book_path, page_name) do
    case book_path |> Path.extname() |> String.downcase() do
      ".pdf" -> extract_pdf_page(book_path, page_name)
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

  defp extract_pdf_page(archive_path, page_name) do
    page_num =
      case Regex.run(~r/page-(\d+)/, page_name) do
        [_, n] -> String.to_integer(n)
        _ -> 1
      end

    tmp = Path.join(System.tmp_dir!(), "stashix_pdf_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    out_prefix = Path.join(tmp, "page")

    try do
      case System.cmd(
             "pdftoppm",
             [
               "-jpeg",
               "-r",
               "150",
               "-f",
               to_string(page_num),
               "-l",
               to_string(page_num),
               archive_path,
               out_prefix
             ],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          case File.ls!(tmp) |> Enum.sort() |> List.first() do
            nil ->
              File.rm_rf!(tmp)
              {:error, :page_not_found}

            fname ->
              data = File.read!(Path.join(tmp, fname))
              File.rm_rf!(tmp)
              {:ok, data}
          end

        {error, _} ->
          File.rm_rf!(tmp)
          {:error, error}
      end
    rescue
      ErlangError ->
        File.rm_rf!(tmp)
        {:error, :pdftoppm_not_found}
    end
  end
end
