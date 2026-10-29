# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Container do
  @moduledoc """
  Finds the metadata XML embedded in a book archive.

  The archive type is sniffed from its first bytes rather than trusted from
  the extension, since `.cbr` files are often zips (and vice versa). Only
  `ComicInfo.xml` / `MetronInfo.xml` at the archive root count, matched
  case-insensitively.

  RAR goes through `unrar` (`lb` / `p`, which the Docker image's 7z-backed
  shim also implements) and 7z through `7z`; a missing tool just means no
  embedded metadata.
  """
  require Logger

  @entries %{"comicinfo.xml" => :comicinfo, "metroninfo.xml" => :metroninfo}

  @type xmls :: %{optional(:comicinfo | :metroninfo) => binary()}

  @doc "The embedded metadata XML of an archive, keyed by format. `%{}` when none."
  @spec read_xml(Path.t()) :: xmls()
  def read_xml(path) do
    case kind(path) do
      :zip -> read_zip(path)
      :rar -> read_with(path, &list_rar/1, &extract_rar/2)
      :seven_zip -> read_with(path, &list_7z/1, &extract_7z/2)
      _ -> %{}
    end
  end

  @doc "Archive type by magic bytes: `:zip`, `:rar`, `:seven_zip` or `nil`."
  def kind(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 6)) do
      {:ok, <<"PK", 3, 4, _::binary>>} -> :zip
      {:ok, <<"Rar!", 0x1A, 7>>} -> :rar
      {:ok, <<"7z", 0xBC, 0xAF, 0x27, 0x1C>>} -> :seven_zip
      _ -> nil
    end
  end

  defp format(name), do: Map.get(@entries, String.downcase(name))

  defp read_zip(path) do
    charlist = String.to_charlist(path)

    with {:ok, entries} <- :zip.list_dir(charlist),
         wanted = for({:zip_file, name, _, _, _, _} <- entries, format(to_string(name)), do: name),
         true <- wanted != [],
         {:ok, files} <- :zip.extract(charlist, [:memory, {:file_list, wanted}]) do
      Map.new(files, fn {name, data} -> {format(to_string(name)), data} end)
    else
      _ -> %{}
    end
  end

  defp read_with(path, list, extract) do
    case list.(path) do
      {:ok, names} ->
        for name <- names, fmt = format(name), {:ok, data} <- [extract.(path, name)], into: %{}, do: {fmt, data}

      {:error, reason} ->
        Logger.debug("No embedded metadata read from #{path}: #{inspect(reason)}")
        %{}
    end
  end

  defp list_rar(path) do
    with {:ok, out} <- cmd("unrar", ["lb", "--", path]), do: {:ok, String.split(out, ~r/\R/, trim: true)}
  end

  defp extract_rar(path, name), do: cmd("unrar", ["p", "-inul", "--", path, name])

  defp list_7z(path) do
    with {:ok, out} <- cmd("7z", ["l", "-ba", "-slt", "--", path]) do
      {:ok, for("Path = " <> name <- String.split(out, ~r/\R/, trim: true), do: name)}
    end
  end

  defp extract_7z(path, name), do: cmd("7z", ["x", "-so", "--", path, name])

  defp cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: false) do
      {out, 0} -> {:ok, out}
      {_, status} -> {:error, {bin, status}}
    end
  rescue
    ErlangError -> {:error, {bin, :not_found}}
  end
end
