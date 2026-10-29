# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Archive do
  @moduledoc """
  Lists and reads entries of book archives (`.cbz`, `.cbr`, `.cb7`, `.epub`).

  The archive type comes from the file's first bytes, not its extension, since
  `.cbr` files are often zips (and vice versa). Zip is read in-process; RAR
  goes through `unrar` (`lb` / `p`, which the Docker image's 7z-backed shim
  also implements) and 7z through `7z`. Options always end with `--`, so names
  starting with `-` are never read as switches.
  """

  @type kind :: :zip | :rar | :seven_zip
  @type entry :: %{name: String.t(), mtime: NaiveDateTime.t() | nil}

  @doc "Archive type by magic bytes, or `nil` when it is none we read."
  @spec kind(Path.t()) :: kind() | nil
  def kind(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 6)) do
      {:ok, <<"PK", 3, 4, _::binary>>} -> :zip
      {:ok, <<"Rar!", 0x1A, 7>>} -> :rar
      {:ok, <<"7z", 0xBC, 0xAF, 0x27, 0x1C>>} -> :seven_zip
      _ -> nil
    end
  end

  @doc """
  Entries in archive order, directories left out (RAR's bare listing can't
  tell them apart, but they never match a page or metadata name). `mtime` is
  the entry's local modification time for zip, else `nil`.
  """
  @spec entries(Path.t()) :: {:ok, [entry()]} | {:error, term()}
  def entries(path) do
    case kind(path) do
      :zip -> zip_entries(path)
      :rar -> with {:ok, out} <- cmd("unrar", ["lb", "--", path]), do: {:ok, rar_entries(out)}
      :seven_zip -> with {:ok, out} <- cmd("7z", ["l", "-ba", "-slt", "--", path]), do: {:ok, seven_zip_entries(out)}
      nil -> {:error, :unsupported_format}
    end
  end

  @doc "Entry names in archive order."
  @spec list(Path.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list(path) do
    with {:ok, entries} <- entries(path), do: {:ok, Enum.map(entries, & &1.name)}
  end

  @doc "The contents of one entry."
  @spec read(Path.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(path, name) do
    case kind(path) do
      :zip -> zip_read(path, name)
      :rar -> cmd("unrar", ["p", "-inul", "--", path, name])
      # -spd: the name is literal, not a wildcard pattern.
      :seven_zip -> cmd("7z", ["x", "-so", "-spd", "--", path, name])
      nil -> {:error, :unsupported_format}
    end
  end

  defp zip_entries(path) do
    with {:ok, entries} <- :zip.list_dir(String.to_charlist(path)) do
      files =
        for {:zip_file, name, info, _comment, _offset, _size} <- entries,
            name = to_string(name),
            not String.ends_with?(name, "/"),
            do: %{name: name, mtime: zip_mtime(info)}

      {:ok, files}
    end
  end

  # info is a #file_info{} record; mtime is local time.
  defp zip_mtime(info) do
    case NaiveDateTime.from_erl(elem(info, 5)) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp zip_read(path, name) do
    case :zip.extract(String.to_charlist(path), [:memory, {:file_list, [String.to_charlist(name)]}]) do
      {:ok, [{_name, data}]} -> {:ok, data}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rar_entries(out), do: for(name <- String.split(out, ~r/\R/, trim: true), do: %{name: name, mtime: nil})

  # `-slt` prints one "Key = Value" block per entry, blocks separated by a blank line.
  defp seven_zip_entries(out) do
    out
    |> String.split(~r/\R\s*\R/, trim: true)
    |> Enum.flat_map(fn block ->
      fields =
        for line <- String.split(block, ~r/\R/), [k, v] <- [String.split(line, " = ", parts: 2)], into: %{}, do: {k, v}

      if fields["Path"] && fields["Folder"] != "+", do: [%{name: fields["Path"], mtime: nil}], else: []
    end)
  end

  defp cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: false) do
      {out, 0} -> {:ok, out}
      {_, status} -> {:error, {bin, status}}
    end
  rescue
    ErlangError -> {:error, {bin, :not_found}}
  end
end
