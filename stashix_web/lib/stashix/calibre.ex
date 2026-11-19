# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre do
  @moduledoc """
  Calibre libraries: a books library filled from a Calibre `metadata.db`
  instead of a folder scan (docs/calibre-plan.md).

  `Stashix.Calibre.Sync` mirrors the database; `Snapshot`, `Reader` and
  `Mapper` read and map it. Stashix keeps out of a Calibre library's folder
  (D8): no folder scans, no metadata written into its files, no automatic
  matching — this module answers "is this one of those?".
  """

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, Library, Series}

  @doc "Whether a library (struct or id), or the library of a book or series, is a Calibre library."
  def library?(%Library{source: source}), do: source == :calibre
  def library?(%Book{library_id: id}), do: library?(id)
  def library?(%Series{library_id: id}), do: library?(id)
  def library?(nil), do: false

  def library?(library_id) when is_binary(library_id) do
    Repo.exists?(from l in Library, where: l.id == ^library_id and l.source == :calibre)
  end

  @doc """
  A library that overlaps `path` (one inside the other) when either is a
  Calibre library — a folder scan would otherwise read Calibre's files as
  books of its own — or nil. `source` is the source of the library being
  saved, `except_id` its id.
  """
  def overlapping(path, source, except_id \\ nil) do
    path = normalize(path)

    from(l in Library, select: l)
    |> then(&if(except_id, do: where(&1, [l], l.id != ^except_id), else: &1))
    |> Repo.all()
    |> Enum.find(fn other ->
      other_path = normalize(other.root_path)
      (inside?(path, other_path) or inside?(other_path, path)) and :calibre in [source, other.source]
    end)
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")
  defp normalize(path), do: path |> Path.expand() |> String.trim_trailing("/")
end
