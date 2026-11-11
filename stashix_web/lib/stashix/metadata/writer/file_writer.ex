# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Writer.FileWriter do
  @moduledoc """
  Writes a book's database metadata back to its files.

    * `.cbz` (that really is a zip) - the archive is rebuilt with
      `MetronInfo.xml` and atomically swapped in. Entries keep their
      timestamps. An existing `ComicInfo.xml` is always rewritten alongside
      (keeping its `<Pages>`); the `write_comicinfo` setting only decides
      whether one is added to archives that have none. Sidecars that already
      sit next to the CBZ are rewritten too, since the reader prefers them.
    * everything else (`.cbr`, `.cb7`, `.pdf`, `.epub`) - sidecars are
      written next to the file (see `Stashix.Metadata.Sidecar`):
      `<book file name>.MetronInfo.xml`, plus `<book file name>.ComicInfo.xml`
      under the same rule as inside a CBZ. EPUBs are not rewritten because
      their zip layout (mimetype first, stored) is strict.

  Afterwards the `BookFile` hash/size/mtime are refreshed so the scanner does
  not treat our own write as a changed file.
  """
  require Logger

  alias Stashix.{Health, Library}
  alias Stashix.Library.{Book, BookFile}
  alias Stashix.Media.Archive
  alias Stashix.Metadata.{Container, Record, Sidecar}
  alias Stashix.Metadata.Format.{ComicInfo, MetronInfo}
  alias Stashix.Scanner

  @stored_exts Enum.map(~w(.jpg .jpeg .png .webp .gif .avif .jxl), &String.to_charlist/1)

  @doc "Writes metadata for every live file of the book."
  def write_book(%Book{} = book, settings) do
    book
    |> then(&Library.get_book_files(&1.id))
    |> Enum.map(&write_file(book, &1, settings))
    |> Enum.find(:ok, &match?({:error, _}, &1))
  end

  def write_file(%Book{} = book, %BookFile{} = file, settings) do
    record = Record.from_book(book)
    metron = MetronInfo.build(record)
    embed? = String.downcase(Path.extname(file.path)) == ".cbz" and Archive.kind(file.path) == :zip

    result =
      case embed? do
        true ->
          existing = Container.comicinfo(file.path)
          comic = if existing != nil or settings["write_comicinfo"], do: build_comic(record, existing, settings)

          case write_cbz(file.path, metron, comic) do
            :ok ->
              sync_existing_sidecars(file.path, record, metron, settings)

            {:error, reason} when reason in [:bad_eocd, :not_a_zip_file, :eocd_not_found] ->
              Logger.warning("CBZ at #{file.path} has bad ZIP structure (#{inspect(reason)}), falling back to sidecar")
              Health.upsert_integrity_result(book.library_id, file.id, file.path, :error, inspect(reason))
              write_sidecars(file.path, record, metron, settings)

            other ->
              other
          end

        false ->
          write_sidecars(file.path, record, metron, settings)
      end

    case result do
      :ok ->
        refresh_file_record(file)

      {:error, reason} = err ->
        Logger.error("Metadata write failed for #{file.path}: #{inspect(reason)}")
        err
    end
  end

  # `existing` is the ComicInfo being replaced; its <Pages> is carried over.
  defp build_comic(record, existing, settings) do
    record
    |> Map.put(:pages, pages(existing))
    |> ComicInfo.build(version: comicinfo_version(settings))
  end

  defp comicinfo_version(settings) do
    version = settings["comicinfo_version"]
    if version in ComicInfo.versions(), do: version, else: ComicInfo.default_version()
  end

  # <Pages> isn't stored in the DB; carry the archive's over as-is.
  defp pages(nil), do: []

  defp pages(xml) do
    case ComicInfo.parse(xml) do
      {:ok, %{pages: pages}} -> pages
      _ -> []
    end
  end

  # Sidecars next to a CBZ are rewritten so they can't shadow the embed, but
  # none are created.
  defp sync_existing_sidecars(path, record, metron, settings) do
    existing = Sidecar.read(path)

    write_types(path,
      metroninfo: existing[:metroninfo] && metron,
      comicinfo: existing[:comicinfo] && build_comic(record, existing[:comicinfo], settings)
    )
  end

  # MetronInfo always; ComicInfo when one is there already or the setting
  # asks for it, like inside a CBZ.
  defp write_sidecars(path, record, metron, settings) do
    existing = Sidecar.read(path)

    comic =
      if existing[:comicinfo] || settings["write_comicinfo"],
        do: build_comic(record, existing[:comicinfo] || Container.comicinfo(path), settings)

    write_types(path, metroninfo: metron, comicinfo: comic)
  end

  # Writes each non-nil `{type, xml}` to its sidecar. An old `<stem>.xml` is
  # removed once the named sidecars have replaced it.
  defp write_types(path, xmls) do
    xmls = Enum.filter(xmls, fn {_type, xml} -> xml end)

    xmls
    |> Enum.map(fn {type, xml} -> write_atomic(Sidecar.path(path, type), xml) end)
    |> Enum.find(:ok, &(&1 != :ok))
    |> case do
      :ok -> if xmls != [] and Sidecar.legacy(path), do: File.rm(Sidecar.legacy_path(path)), else: :ok
      error -> error
    end
  end

  defp write_atomic(target, xml) do
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
  # `comic_xml` nil keeps the archive's existing ComicInfo.xml as it is.
  def write_cbz(path, metron_xml, comic_xml) do
    work_dir = Path.join(System.tmp_dir!(), "stashix-meta-#{System.unique_integer([:positive])}")
    tmp_zip = Path.join(Path.dirname(path), ".#{Path.basename(path)}.stashix-tmp")

    try do
      File.mkdir_p!(work_dir)

      replaced = if comic_xml, do: ~w(metroninfo.xml comicinfo.xml), else: ~w(metroninfo.xml)

      with {:ok, names} <- extract_entries(path, work_dir, replaced),
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

  # Extracts file entries (in archive order) except the metadata XML being
  # replaced, keeping each entry's timestamp. Returns the charlist names to
  # re-add. Rejects unsafe paths (zip-slip).
  defp extract_entries(path, work_dir, replaced) do
    with {:ok, handle} <- :zip.zip_open(String.to_charlist(path), [:memory]) do
      try do
        {:ok, entries} = :zip.zip_list_dir(handle)

        entries
        |> Enum.flat_map(fn
          {:zip_file, name, info, _comment, _offset, _size} ->
            if elem(info, 2) == :directory, do: [], else: [{name, elem(info, 5)}]

          _ ->
            []
        end)
        |> Enum.reject(fn {name, _} -> String.downcase(Path.basename(to_string(name))) in replaced end)
        |> Enum.reduce_while({:ok, []}, fn {name, mtime}, {:ok, acc} ->
          rel = to_string(name)

          if safe_path?(rel) do
            {:ok, {_, data}} = :zip.zip_get(name, handle)
            dest = Path.join(work_dir, rel)
            File.mkdir_p!(Path.dirname(dest))
            File.write!(dest, data)
            # :zip stores and restores local time; keep the entry's own.
            :file.change_time(String.to_charlist(dest), mtime)
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
