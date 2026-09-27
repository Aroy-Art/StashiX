defmodule Stashix.Metadata.Writer.FileWriter do
  @moduledoc """
  Writes a book's database metadata back to its files.

    * `.cbz` - the archive is rebuilt with `MetronInfo.xml` (and optionally a
      `ComicInfo.xml` compat copy) and atomically swapped in.
    * everything else (`.cbr`, `.cb7`, `.pdf`, `.epub`) - a MetronInfo sidecar
      `<book file name>.xml` is written next to the file. EPUBs are not
      rewritten because their zip layout (mimetype first, stored) is strict.

  Afterwards the `BookFile` hash/size/mtime are refreshed so the scanner does
  not treat our own write as a changed file.
  """
  require Logger

  alias Stashix.Library
  alias Stashix.Library.{Book, BookFile}
  alias Stashix.Metadata.Writer.{MetronInfoXml, ComicInfoXml}
  alias Stashix.Scanner

  @metadata_entries ~w(metroninfo.xml comicinfo.xml)
  @stored_exts Enum.map(~w(.jpg .jpeg .png .webp .gif .avif .jxl), &String.to_charlist/1)

  @doc "Writes metadata for every live file of the book."
  def write_book(%Book{} = book, settings) do
    book
    |> then(&Library.get_book_files(&1.id))
    |> Enum.map(&write_file(book, &1, settings))
    |> Enum.find(:ok, &match?({:error, _}, &1))
  end

  def write_file(%Book{} = book, %BookFile{} = file, settings) do
    metron = MetronInfoXml.build(book)
    comic = if settings["write_comicinfo"], do: ComicInfoXml.build(book)

    result =
      case String.downcase(Path.extname(file.path)) do
        ".cbz" -> write_cbz(file.path, metron, comic)
        _ -> write_sidecar(file.path, metron)
      end

    case result do
      :ok ->
        refresh_file_record(file)

      {:error, reason} = err ->
        Logger.error("Metadata write failed for #{file.path}: #{inspect(reason)}")
        err
    end
  end

  @doc "Path of the sidecar metadata file for a book file."
  def sidecar_path(path), do: Path.rootname(path) <> ".xml"

  defp write_sidecar(path, xml) do
    target = sidecar_path(path)
    tmp = Path.join(Path.dirname(target), ".#{Path.basename(target)}.stashix-tmp")
    Scanner.FileWatcher.suppress(target)

    with :ok <- File.write(tmp, xml),
         :ok <- File.rename(tmp, target) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  @doc false
  def write_cbz(path, metron_xml, comic_xml) do
    work_dir = Path.join(System.tmp_dir!(), "stashix-meta-#{System.unique_integer([:positive])}")
    tmp_zip = Path.join(Path.dirname(path), ".#{Path.basename(path)}.stashix-tmp")

    try do
      File.mkdir_p!(work_dir)

      with {:ok, names} <- extract_entries(path, work_dir),
           names = add_xml(names, work_dir, "MetronInfo.xml", metron_xml),
           names = add_xml(names, work_dir, "ComicInfo.xml", comic_xml),
           {:ok, _} <-
             :zip.create(String.to_charlist(tmp_zip), names,
               cwd: String.to_charlist(work_dir),
               uncompress: {:add, @stored_exts}
             ),
           :ok <- verify(tmp_zip, length(names)),
           :ok <- copy_mode(path, tmp_zip) do
        Scanner.FileWatcher.suppress(path)
        File.rename(tmp_zip, path)
      else
        {:error, _} = error -> error
        other -> {:error, other}
      end
    rescue
      e -> {:error, Exception.message(e)}
    after
      File.rm_rf(work_dir)
      File.rm(tmp_zip)
    end
  end

  # Extracts file entries (in archive order) except old metadata XML. Returns
  # the charlist names to re-add. Rejects unsafe paths (zip-slip).
  defp extract_entries(path, work_dir) do
    with {:ok, handle} <- :zip.zip_open(String.to_charlist(path), [:memory]) do
      try do
        {:ok, entries} = :zip.zip_list_dir(handle)

        entries
        |> Enum.flat_map(fn
          {:zip_file, name, info, _comment, _offset, _size} ->
            if elem(info, 2) == :directory, do: [], else: [name]

          _ ->
            []
        end)
        |> Enum.reject(&(String.downcase(Path.basename(to_string(&1))) in @metadata_entries))
        |> Enum.reduce_while({:ok, []}, fn name, {:ok, acc} ->
          rel = to_string(name)

          if safe_path?(rel) do
            {:ok, {_, data}} = :zip.zip_get(name, handle)
            dest = Path.join(work_dir, rel)
            File.mkdir_p!(Path.dirname(dest))
            File.write!(dest, data)
            {:cont, {:ok, [name | acc]}}
          else
            {:halt, {:error, {:unsafe_entry, rel}}}
          end
        end)
        |> case do
          {:ok, names} -> {:ok, Enum.reverse(names)}
          error -> error
        end
      after
        :zip.zip_close(handle)
      end
    end
  end

  defp safe_path?(rel) do
    Path.type(rel) == :relative and not Enum.member?(Path.split(rel), "..")
  end

  defp add_xml(names, _work_dir, _name, nil), do: names

  defp add_xml(names, work_dir, name, xml) do
    File.write!(Path.join(work_dir, name), xml)
    names ++ [String.to_charlist(name)]
  end

  defp verify(zip, expected) do
    case :zip.list_dir(String.to_charlist(zip)) do
      {:ok, [_comment | entries]} when length(entries) >= expected -> :ok
      {:ok, _} -> {:error, :verify_failed}
      error -> error
    end
  end

  defp copy_mode(src, dest) do
    case File.stat(src) do
      {:ok, %{mode: mode}} -> File.chmod(dest, Bitwise.band(mode, 0o7777))
      error -> error
    end
  end

  defp refresh_file_record(%BookFile{path: path} = file) do
    case File.stat(path) do
      {:ok, stat} ->
        Library.update_book_file(file, %{
          file_size: stat.size,
          file_hash: Scanner.compute_hash(path, stat.size),
          last_modified: NaiveDateTime.from_erl!(stat.mtime)
        })

        :ok

      error ->
        error
    end
  end
end
