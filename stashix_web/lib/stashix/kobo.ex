# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Kobo do
  @moduledoc """
  Kobo sync, seen from the library: which books a Kobo gets and what it was
  sent before (`StashixWeb.KoboController` speaks the Kobo store API).

  A Kobo syncs with one of the user's app passwords (it is in the store URL
  set on the device), and gets every book with an EPUB the user may read and
  download. `kobo_synced_books` remembers, per app password, which books it
  was sent and when, so each sync sends only what was added, changed or
  removed since. Books go out as KEPUB, converted with `kepubify` when it is
  installed (`kepub/1`), else as plain EPUB; fixed-layout EPUBs as they are.
  """

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Access, Book, BookFile}

  @doc """
  Books a Kobo may have: `%{id, modified}` for every visible, non-deleted
  book with an EPUB in a library the user may download from. `modified` is
  the later of the book's and its EPUB's last change.
  """
  def books(%Access{} = access) do
    epubs =
      from(f in BookFile,
        where: f.format == :epub and is_nil(f.deleted_at),
        group_by: f.book_id,
        select: %{book_id: f.book_id, updated_at: max(f.updated_at)}
      )

    from(b in Access.books(access),
      join: f in subquery(epubs),
      on: f.book_id == b.id,
      where: is_nil(b.deleted_at),
      select: %{id: b.id, modified: fragment("GREATEST(?, ?)", b.updated_at, f.updated_at)}
    )
    |> downloadable(access)
    |> Repo.all()
  end

  defp downloadable(query, %Access{all?: true}), do: query
  defp downloadable(query, %Access{downloads: ids}), do: where(query, [b], b.library_id in ^ids)

  @doc "The books an app password's Kobo was sent: `%{book_id => synced_at}` (`NaiveDateTime`, UTC)."
  def synced(app_password_id) do
    from(s in "kobo_synced_books",
      where: s.app_password_id == type(^app_password_id, :binary_id),
      select: {type(s.book_id, :binary_id), s.synced_at}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Records books as sent now."
  def mark_synced(_app_password_id, []), do: :ok

  def mark_synced(app_password_id, book_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, app_password_id} = Ecto.UUID.dump(app_password_id)

    rows =
      for id <- book_ids do
        {:ok, id} = Ecto.UUID.dump(id)
        %{app_password_id: app_password_id, book_id: id, synced_at: now}
      end

    Repo.insert_all("kobo_synced_books", rows,
      on_conflict: {:replace, [:synced_at]},
      conflict_target: [:app_password_id, :book_id]
    )

    :ok
  end

  @doc "Forgets books the Kobo was told are gone."
  def mark_removed(_app_password_id, []), do: :ok

  def mark_removed(app_password_id, book_ids) do
    from(s in "kobo_synced_books",
      where:
        s.app_password_id == type(^app_password_id, :binary_id) and s.book_id in type(^book_ids, {:array, :binary_id})
    )
    |> Repo.delete_all()

    :ok
  end

  ## Shelves (collections)

  @doc """
  The collections an app password's Kobo has as shelves: `%{collection_id
  => items_hash}`. No foreign key on the collection: a deleted collection
  stays listed until the device is told it is gone.
  """
  def synced_shelves(app_password_id) do
    from(s in "kobo_synced_collections",
      where: s.app_password_id == type(^app_password_id, :binary_id),
      select: {type(s.collection_id, :binary_id), s.items_hash}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Records shelves as sent with these hashes: `[{collection_id, items_hash}]`."
  def mark_shelves(_app_password_id, []), do: :ok

  def mark_shelves(app_password_id, shelves) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    {:ok, ap} = Ecto.UUID.dump(app_password_id)

    rows =
      for {id, hash} <- shelves do
        {:ok, id} = Ecto.UUID.dump(id)
        %{app_password_id: ap, collection_id: id, items_hash: hash, synced_at: now}
      end

    Repo.insert_all("kobo_synced_collections", rows,
      on_conflict: {:replace, [:items_hash, :synced_at]},
      conflict_target: [:app_password_id, :collection_id]
    )

    :ok
  end

  @doc "Forgets shelves the device was told are gone (all of them with `:all`)."
  def forget_shelves(app_password_id, :all) do
    from(s in "kobo_synced_collections", where: s.app_password_id == type(^app_password_id, :binary_id))
    |> Repo.delete_all()

    :ok
  end

  def forget_shelves(_app_password_id, []), do: :ok

  def forget_shelves(app_password_id, ids) do
    from(s in "kobo_synced_collections",
      where:
        s.app_password_id == type(^app_password_id, :binary_id) and
          s.collection_id in type(^ids, {:array, :binary_id})
    )
    |> Repo.delete_all()

    :ok
  end

  @doc "What a shelf's hash covers: its name and its books, in order."
  def shelf_hash(name, book_ids),
    do: :crypto.hash(:sha256, Enum.join([name | book_ids], "\n")) |> Base.url_encode64(padding: false)

  @doc "Books with everything a Kobo's metadata needs."
  def load_books(ids) do
    from(b in Book, where: b.id in ^ids, preload: [:series, :publishers, :files, credits: :creator])
    |> Repo.all()
  end

  @doc "The EPUB a Kobo gets for a book, or nil."
  def epub(%Book{files: files}) when is_list(files) do
    files
    |> Enum.filter(&(&1.format == :epub and is_nil(&1.deleted_at)))
    |> Enum.sort_by(&kepub?/1, :desc)
    |> List.first()
  end

  @doc "Whether an EPUB file is already a KEPUB."
  def kepub?(%BookFile{path: path}), do: path |> String.downcase() |> String.ends_with?(".kepub.epub")

  @doc "Whether an EPUB is fixed layout (page images): it goes out as it is."
  def fixed_layout?(%BookFile{content_kind: :images}), do: true
  def fixed_layout?(_file), do: false

  @doc "Whether `kepubify` is installed to convert EPUBs."
  def kepubify?, do: kepubify() != nil

  # `config :stashix, kepubify: path` picks the binary (nil: none); else it is looked up.
  defp kepubify do
    case Application.fetch_env(:stashix, :kepubify) do
      {:ok, path} -> path
      :error -> System.find_executable("kepubify")
    end
  end

  @doc """
  The KEPUB of an EPUB file, converted on first use and kept in the cache
  (keyed by the file's hash, so a changed file is converted again).
  """
  def kepub(%BookFile{} = file) do
    dir = Path.join(cache_dir(), "kepub")
    key = :crypto.hash(:sha256, "#{file.path}:#{file.file_hash}") |> Base.url_encode64(padding: false)
    out = Path.join(dir, key <> ".kepub.epub")

    cond do
      File.exists?(out) ->
        {:ok, out}

      bin = kepubify() ->
        File.mkdir_p!(dir)
        tmp = Path.join(dir, "#{key}.#{System.unique_integer([:positive])}.kepub.epub")

        case System.cmd(bin, ["-o", tmp, file.path], stderr_to_stdout: true) do
          {_, 0} ->
            File.rename!(tmp, out)
            {:ok, out}

          {output, status} ->
            File.rm(tmp)
            {:error, {:kepubify, status, output}}
        end

      true ->
        {:error, :no_kepubify}
    end
  end

  defp cache_dir do
    Application.get_env(:stashix, :page_cache_dir, "/tmp/stashix/cache/pages") |> Path.dirname()
  end
end
