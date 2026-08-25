defmodule Stashix.Media.Extractor do
  @image_exts ~w(.jpg .jpeg .png .gif .webp)

  def list_pages(book_path) do
    ext = book_path |> Path.extname() |> String.downcase()

    case ext do
      ".cbz" -> list_zip_pages(book_path)
      ".epub" -> list_zip_pages(book_path)
      ".cbr" -> list_rar_pages(book_path)
      ".cb7" -> list_7z_pages(book_path)
      ".pdf" -> list_pdf_pages(book_path)
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

  defp list_zip_pages(path) do
    case :zip.list_dir(String.to_charlist(path)) do
      {:ok, entries} ->
        pages =
          entries
          |> Enum.filter(fn
            {:zip_file, name, _info, _comment, _offset, _comp_size} ->
              name_str = to_string(name)
              String.downcase(Path.extname(name_str)) in @image_exts

            _ ->
              false
          end)
          |> Enum.map(fn {:zip_file, name, _info, _comment, _offset, _comp_size} ->
            to_string(name)
          end)
          |> Enum.sort()

        {:ok, pages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_rar_pages(path) do
    case System.cmd("unrar", ["lb", path], stderr_to_stdout: true) do
      {output, 0} ->
        pages =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(fn name ->
            String.downcase(Path.extname(name)) in @image_exts
          end)
          |> Enum.sort()

        {:ok, pages}

      {error, _} ->
        {:error, error}
    end
  end

  defp list_7z_pages(path) do
    case System.cmd("7z", ["l", "-ba", "-slt", path], stderr_to_stdout: true) do
      {output, 0} ->
        pages =
          output
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "Path = "))
          |> Enum.map(&String.replace_leading(&1, "Path = ", ""))
          |> Enum.filter(fn name ->
            String.downcase(Path.extname(name)) in @image_exts
          end)
          |> Enum.sort()

        {:ok, pages}

      {error, _} ->
        {:error, error}
    end
  end

  defp list_pdf_pages(path) do
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

        page_names = Enum.map(1..max(pages, 1), &"page-#{String.pad_leading(to_string(&1), 4, "0")}.jpg")
        {:ok, page_names}

      {error, _} ->
        {:error, error}
    end
  end

  defp extract_page(book_path, page_name) do
    ext = book_path |> Path.extname() |> String.downcase()

    case ext do
      cbz when cbz in [".cbz", ".epub"] ->
        extract_zip_page(book_path, page_name)

      ".cbr" ->
        extract_rar_page(book_path, page_name)

      ".cb7" ->
        extract_7z_page(book_path, page_name)

      ".pdf" ->
        extract_pdf_page(book_path, page_name)

      _ ->
        {:error, :unsupported_format}
    end
  end

  defp extract_zip_page(archive_path, page_name) do
    path_charlist = String.to_charlist(archive_path)
    file_charlist = String.to_charlist(page_name)

    case :zip.extract(path_charlist, [:memory, {:file_list, [file_charlist]}]) do
      {:ok, [{_name, data}]} -> {:ok, data}
      {:ok, []} -> {:error, :page_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_rar_page(archive_path, page_name) do
    case System.cmd("unrar", ["p", "-inul", archive_path, page_name], stderr_to_stdout: false) do
      {data, 0} -> {:ok, data}
      {error, _} -> {:error, error}
    end
  end

  defp extract_7z_page(archive_path, page_name) do
    tmp = Path.join(System.tmp_dir!(), "stashix_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    case System.cmd("7z", ["e", archive_path, page_name, "-o#{tmp}", "-y"],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        dest = Path.join(tmp, Path.basename(page_name))

        case File.read(dest) do
          {:ok, data} ->
            File.rm_rf!(tmp)
            {:ok, data}

          error ->
            File.rm_rf!(tmp)
            error
        end

      {error, _} ->
        File.rm_rf!(tmp)
        {:error, error}
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

    case System.cmd(
           "pdftoppm",
           ["-jpeg", "-r", "150", "-f", to_string(page_num), "-l", to_string(page_num), archive_path, out_prefix],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        case File.ls!(tmp) |> List.first() do
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
  end
end
