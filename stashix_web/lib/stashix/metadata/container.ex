# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Container do
  @moduledoc """
  Finds the metadata XML embedded in a book archive (zip, RAR or 7z, detected
  by content via `Stashix.Media.Archive`, like the page reader).

  Only `ComicInfo.xml` / `MetronInfo.xml` at the archive root count, matched
  case-insensitively.
  """
  require Logger

  alias Stashix.Media.Archive

  @entries %{"comicinfo.xml" => :comicinfo, "metroninfo.xml" => :metroninfo}

  # A ComicInfo.xml this much older than the MetronInfo.xml beside it was not
  # written with it (e.g. kept while ComicInfo write-back is off).
  @stale_after_s 60

  @type found :: %{data: binary(), mtime: NaiveDateTime.t() | nil}
  @type xmls :: %{optional(:comicinfo | :metroninfo) => found()}

  @doc "The embedded metadata XML of an archive, keyed by format. `%{}` when none."
  @spec read_xml(Path.t()) :: xmls()
  def read_xml(path) do
    with {:ok, entries} <- Archive.entries(path) do
      for %{name: name, mtime: mtime} <- entries,
          fmt = format(name),
          {:ok, data} <- [Archive.read(path, name)],
          into: %{},
          do: {fmt, %{data: data, mtime: mtime}}
    else
      {:error, reason} ->
        Logger.debug("No embedded metadata read from #{path}: #{inspect(reason)}")
        %{}
    end
  end

  @doc """
  Whether the ComicInfo in `xmls` predates the MetronInfo beside it, so it
  must not override anything. Unknown timestamps count as written together.
  """
  @spec stale_comicinfo?(xmls()) :: boolean()
  def stale_comicinfo?(%{comicinfo: %{mtime: %NaiveDateTime{} = c}, metroninfo: %{mtime: %NaiveDateTime{} = m}}),
    do: NaiveDateTime.diff(m, c) > @stale_after_s

  def stale_comicinfo?(_xmls), do: false

  @doc "The ComicInfo.xml embedded in an archive, or `nil`."
  def comicinfo(path) do
    with {:ok, entries} <- Archive.entries(path),
         %{name: name} <- Enum.find(entries, &(format(&1.name) == :comicinfo)),
         {:ok, data} <- Archive.read(path, name) do
      data
    else
      _ -> nil
    end
  end

  defp format(name), do: Map.get(@entries, String.downcase(name))
end
