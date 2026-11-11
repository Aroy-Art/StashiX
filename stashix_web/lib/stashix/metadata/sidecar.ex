# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Sidecar do
  @moduledoc """
  Metadata sidecars next to a book file, one per format:
  `<stem>.MetronInfo.xml` and `<stem>.ComicInfo.xml`.

  Older versions wrote a single `<stem>.xml` holding either format. It is
  still read (sniffed by root tag) when there is no named sidecar of that
  format, and `Stashix.Metadata.Writer.FileWriter` removes it once the named
  sidecars replace it.
  """

  @names %{metroninfo: "MetronInfo", comicinfo: "ComicInfo"}

  def types, do: Map.keys(@names)

  @doc "Path of the `type` sidecar for a book file."
  def path(file_path, type), do: Path.rootname(file_path) <> ".#{Map.fetch!(@names, type)}.xml"

  @doc "Path of the old single `<stem>.xml` sidecar."
  def legacy_path(file_path), do: Path.rootname(file_path) <> ".xml"

  @doc "The sidecars present for a book file, as `%{type => xml}`."
  def read(file_path) do
    named =
      Enum.flat_map(types(), fn type ->
        if data = read_file(path(file_path, type)), do: [{type, data}], else: []
      end)
      |> Map.new()

    case legacy(file_path) do
      {type, data} -> Map.put_new(named, type, data)
      nil -> named
    end
  end

  @doc "`{type, xml}` of the old `<stem>.xml` sidecar, or nil."
  def legacy(file_path) do
    with data when is_binary(data) <- read_file(legacy_path(file_path)),
         type when type != nil <- sniff(data) do
      {type, data}
    else
      _ -> nil
    end
  end

  @doc """
  The book file stem a sidecar belongs to: `Batman 001.MetronInfo.xml`,
  `Batman 001.ComicInfo.xml` and `Batman 001.xml` all give `Batman 001`.
  """
  def stem(sidecar_path) do
    base = Path.rootname(sidecar_path)

    if Path.extname(base) in Enum.map(Map.values(@names), &".#{&1}"),
      do: Path.rootname(base),
      else: base
  end

  defp sniff(data) do
    cond do
      String.contains?(data, "<MetronInfo") -> :metroninfo
      String.contains?(data, "<ComicInfo") -> :comicinfo
      true -> nil
    end
  end

  defp read_file(path) do
    with true <- File.regular?(path),
         {:ok, data} <- File.read(path) do
      data
    else
      _ -> nil
    end
  end
end
