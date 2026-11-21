# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Koreader do
  @moduledoc """
  KOReader's progress sync (the kosync protocol), seen from the library:
  which book a KOReader document is, and how its positions map onto
  Stashix progress.

  KOReader names a document by a partial MD5 of the file ("Binary" document
  matching, its default): 1 KB samples at offsets 0, 1 KB, 4 KB, 16 KB … up
  to 1 GB. Each book file keeps that hash with the `file_hash` it was taken
  from; files without a current one are hashed when a lookup misses, so
  nothing has to happen at scan time.

  Positions: page books (comics, PDFs) send the page number, from 1.
  Reflowable books send an XPointer such as
  `/body/DocFragment[3]/body/p[5]/text().0`, where the fragment is the
  spine item, from 1. Stashix keeps KOReader's XPointer to hand back
  exactly, and otherwise points KOReader at the start of the chapter.
  """

  import Ecto.Query
  import Bitwise

  alias Stashix.Repo
  alias Stashix.Library.{Access, BookFile}

  @sample 1024
  @offsets [0 | for(i <- 0..10, do: @sample <<< (2 * i))]

  @doc "KOReader's partial MD5 of a file, in hex; nil when it can't be read."
  def partial_md5(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, file} ->
        try do
          @offsets
          |> Enum.reduce_while(:crypto.hash_init(:md5), fn offset, md5 ->
            case :file.pread(file, offset, @sample) do
              {:ok, data} -> {:cont, :crypto.hash_update(md5, data)}
              _eof -> {:halt, md5}
            end
          end)
          |> :crypto.hash_final()
          |> Base.encode16(case: :lower)
        after
          File.close(file)
        end

      {:error, _} ->
        nil
    end
  end

  @doc """
  The book a KOReader document hash names, among those `access` may see:
  `{:ok, book, book_file}`, `{:error, :not_found}` or `{:error, :ambiguous}`
  (the same file in two places).
  """
  def find(access, hash) when is_binary(hash) do
    hash = String.downcase(hash)

    case lookup(access, hash) do
      [] ->
        fill_hashes()
        lookup(access, hash) |> one()

      found ->
        one(found)
    end
  end

  defp one([{book, file}]), do: {:ok, book, file}
  defp one([]), do: {:error, :not_found}
  defp one(_several), do: {:error, :ambiguous}

  defp lookup(access, hash) do
    from(f in BookFile,
      join: b in ^Access.books(access),
      on: b.id == f.book_id,
      where:
        f.koreader_hash == ^hash and f.koreader_hash_of == f.file_hash and is_nil(f.deleted_at) and
          is_nil(b.deleted_at),
      select: {b, f}
    )
    |> Repo.all()
    |> Enum.uniq_by(fn {b, _f} -> b.id end)
  end

  @doc "Hashes every file whose KOReader hash is missing or out of date. Returns how many."
  def fill_hashes do
    from(f in BookFile,
      where: is_nil(f.deleted_at) and (is_nil(f.koreader_hash_of) or f.koreader_hash_of != f.file_hash),
      select: {f.id, f.path, f.file_hash}
    )
    |> Repo.all()
    |> Enum.count(fn {id, path, file_hash} ->
      case partial_md5(path) do
        nil ->
          false

        hash ->
          from(f in BookFile, where: f.id == ^id)
          |> Repo.update_all(set: [koreader_hash: hash, koreader_hash_of: file_hash])

          true
      end
    end)
  end

  ## Positions

  @doc "The spine item an XPointer points into, from 0; nil if it names none."
  def fragment_index("/body/DocFragment[" <> rest) do
    case Integer.parse(rest) do
      {n, "]" <> _} when n > 0 -> n - 1
      _ -> nil
    end
  end

  # After a jump from the table of contents: "#_doc_fragment_44_ c37", from 0.
  def fragment_index("#_doc_fragment_" <> rest) do
    case Integer.parse(rest) do
      {n, _} when n >= 0 -> n
      _ -> nil
    end
  end

  def fragment_index(_), do: nil

  @doc "The href of the EPUB spine item at `index`, or nil."
  def spine_href(%BookFile{format: :epub, path: path}, index) when is_integer(index) do
    case Stashix.Media.Epub.package(path) do
      {:ok, %{spine: spine}} -> spine |> Enum.at(index) |> then(&(&1 && &1.item.href))
      _ -> nil
    end
  end

  def spine_href(_file, _index), do: nil

  @doc "An XPointer to the start of the EPUB spine item with `href` (the first one when unknown)."
  def chapter_xpointer(%BookFile{format: :epub, path: path}, href) when is_binary(href) do
    index =
      case Stashix.Media.Epub.package(path) do
        {:ok, %{spine: spine}} -> Enum.find_index(spine, &(&1.item.href == href))
        _ -> nil
      end

    "/body/DocFragment[#{(index || 0) + 1}].0"
  end

  def chapter_xpointer(_file, _href), do: "/body/DocFragment[1].0"
end
