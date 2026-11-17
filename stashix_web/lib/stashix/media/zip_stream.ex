# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.ZipStream do
  @moduledoc """
  Writes a ZIP archive piece by piece while reading the files, so a series
  download never sits in memory or in a temp file.

  Entries are stored, not deflated: comic archives and PDFs are compressed
  already. Because of that the archive's exact size is known before the first
  byte (`size/1`), which lets the response carry a `content-length` and the
  browser show real progress. CRCs go in a data descriptor after each file.
  ZIP64 records are used only where a size, offset or count needs them.
  """

  import Bitwise

  @max32 0xFFFFFFFF
  @max16 0xFFFF
  @read_chunk 1_048_576
  # Version made by: Unix host, spec 4.5. Unix host makes extractors honour the mode bits below.
  @made_by 3 <<< 8 ||| 45
  # Bit 3: sizes and CRC in a data descriptor. Bit 11: names are UTF-8.
  @flags 0x0808
  # Regular file, rw-r--r--, in the high half of the external attributes.
  @external_attr 0o100644 <<< 16

  defmodule Entry do
    @moduledoc false
    defstruct [:name, :path, :size, :time, :date, :offset]
  end

  @doc """
  Plans an archive from `{name, path}` pairs: reads each file's size and
  modification time and works out where it goes. Missing files are dropped.
  """
  def plan(files) do
    {entries, _offset} =
      Enum.flat_map_reduce(files, 0, fn {name, path}, offset ->
        case File.stat(path, time: :local) do
          {:ok, %{type: :regular, size: size, mtime: mtime}} ->
            {time, date} = dos_time(mtime)
            entry = %Entry{name: name, path: path, size: size, time: time, date: date, offset: offset}
            {[entry], offset + local_size(entry)}

          _ ->
            {[], offset}
        end
      end)

    entries
  end

  @doc "Exact byte size of the archive `write/3` produces for planned `entries`."
  def size(entries) do
    cd_offset = Enum.reduce(entries, 0, &(&2 + local_size(&1)))
    cd_size = entries |> Enum.map(&IO.iodata_length(central_header(&1, 0))) |> Enum.sum()
    cd_offset + cd_size + IO.iodata_length(end_records(length(entries), cd_size, cd_offset))
  end

  @doc """
  Writes planned `entries`, handing each piece of iodata to `emit`, a
  `(iodata, acc -> {:ok, acc} | {:error, reason})` fun. Stops at the first
  error, including a file whose size changed since it was planned.
  """
  def write(entries, acc, emit) do
    result =
      Enum.reduce_while(entries, {:ok, acc, []}, fn entry, {:ok, acc, crcs} ->
        with {:ok, acc} <- emit.(local_header(entry), acc),
             {:ok, acc, crc} <- write_data(entry, acc, emit),
             {:ok, acc} <- emit.(descriptor(entry, crc), acc) do
          {:cont, {:ok, acc, [crc | crcs]}}
        else
          error -> {:halt, error}
        end
      end)

    with {:ok, acc, crcs} <- result do
      central = entries |> Enum.zip(Enum.reverse(crcs)) |> Enum.map(fn {e, crc} -> central_header(e, crc) end)
      cd_offset = Enum.reduce(entries, 0, &(&2 + local_size(&1)))
      cd_size = IO.iodata_length(central)
      emit.([central, end_records(length(entries), cd_size, cd_offset)], acc)
    end
  end

  defp write_data(entry, acc, emit) do
    entry.path
    |> File.stream!(@read_chunk)
    |> Enum.reduce_while({:ok, acc, :erlang.crc32(<<>>), 0}, fn chunk, {:ok, acc, crc, read} ->
      case emit.(chunk, acc) do
        {:ok, acc} -> {:cont, {:ok, acc, :erlang.crc32(crc, chunk), read + byte_size(chunk)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc, crc, read} when read == entry.size -> {:ok, acc, crc}
      {:ok, _acc, _crc, _read} -> {:error, {:file_changed, entry.path}}
      error -> error
    end
  rescue
    e in File.Error -> {:error, e.reason}
  end

  # Entries at or over 4 GiB carry ZIP64 sizes in the local header and descriptor.
  defp zip64_size?(%Entry{size: size}), do: size >= @max32

  defp local_size(entry),
    do: IO.iodata_length(local_header(entry)) + entry.size + IO.iodata_length(descriptor(entry, 0))

  defp local_header(entry) do
    {version, size32, extra} =
      if zip64_size?(entry),
        do: {45, @max32, <<0x0001::little-16, 16::little-16, 0::little-64, 0::little-64>>},
        else: {20, 0, <<>>}

    [
      <<0x04034B50::little-32, version::little-16, @flags::little-16, 0::little-16, entry.time::little-16,
        entry.date::little-16, 0::little-32, size32::little-32, size32::little-32, byte_size(entry.name)::little-16,
        byte_size(extra)::little-16>>,
      entry.name,
      extra
    ]
  end

  defp descriptor(entry, crc) do
    if zip64_size?(entry),
      do: <<0x08074B50::little-32, crc::little-32, entry.size::little-64, entry.size::little-64>>,
      else: <<0x08074B50::little-32, crc::little-32, entry.size::little-32, entry.size::little-32>>
  end

  defp central_header(entry, crc) do
    big_size = zip64_size?(entry)
    big_offset = entry.offset >= @max32

    zip64_fields =
      if(big_size, do: <<entry.size::little-64, entry.size::little-64>>, else: <<>>) <>
        if big_offset, do: <<entry.offset::little-64>>, else: <<>>

    extra =
      if zip64_fields == <<>>,
        do: <<>>,
        else: <<0x0001::little-16, byte_size(zip64_fields)::little-16, zip64_fields::binary>>

    version = if extra == <<>>, do: 20, else: 45
    size32 = if big_size, do: @max32, else: entry.size
    offset32 = if big_offset, do: @max32, else: entry.offset

    [
      <<0x02014B50::little-32, @made_by::little-16, version::little-16, @flags::little-16, 0::little-16,
        entry.time::little-16, entry.date::little-16, crc::little-32, size32::little-32, size32::little-32,
        byte_size(entry.name)::little-16, byte_size(extra)::little-16, 0::little-16, 0::little-16, 0::little-16,
        @external_attr::little-32, offset32::little-32>>,
      entry.name,
      extra
    ]
  end

  defp end_records(count, cd_size, cd_offset) do
    if count >= @max16 or cd_size >= @max32 or cd_offset >= @max32 do
      zip64_end_offset = cd_offset + cd_size

      [
        <<0x06064B50::little-32, 44::little-64, @made_by::little-16, 45::little-16, 0::little-32, 0::little-32,
          count::little-64, count::little-64, cd_size::little-64, cd_offset::little-64>>,
        <<0x07064B50::little-32, 0::little-32, zip64_end_offset::little-64, 1::little-32>>,
        <<0x06054B50::little-32, 0::little-16, 0::little-16, @max16::little-16, @max16::little-16, @max32::little-32,
          @max32::little-32, 0::little-16>>
      ]
    else
      <<0x06054B50::little-32, 0::little-16, 0::little-16, count::little-16, count::little-16, cd_size::little-32,
        cd_offset::little-32, 0::little-16>>
    end
  end

  # MS-DOS date/time, which cannot go before 1980.
  defp dos_time({{year, _, _}, _}) when year < 1980, do: dos_time({{1980, 1, 1}, {0, 0, 0}})

  defp dos_time({{year, month, day}, {hour, min, sec}}),
    do: {hour <<< 11 ||| min <<< 5 ||| div(sec, 2), (year - 1980) <<< 9 ||| month <<< 5 ||| day}
end
