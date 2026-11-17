# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.ZipStreamTest do
  use ExUnit.Case, async: true

  alias Stashix.Media.ZipStream

  @moduletag :tmp_dir

  test "writes a stored archive whose size is known up front", %{tmp_dir: tmp} do
    big = :crypto.strong_rand_bytes(3_000_000)
    File.write!(Path.join(tmp, "a.cbz"), big)
    File.write!(Path.join(tmp, "b.pdf"), "hello")
    File.write!(Path.join(tmp, "empty.cbr"), "")

    entries =
      ZipStream.plan([
        {"Série 001.cbz", Path.join(tmp, "a.cbz")},
        {"b.pdf", Path.join(tmp, "b.pdf")},
        {"empty.cbr", Path.join(tmp, "empty.cbr")},
        {"gone.cbz", Path.join(tmp, "missing.cbz")}
      ])

    assert {:ok, iodata} = ZipStream.write(entries, [], fn data, acc -> {:ok, [acc, data]} end)
    zip = IO.iodata_to_binary(iodata)
    assert byte_size(zip) == ZipStream.size(entries)

    {:ok, files} = :zip.unzip(zip, [:memory])

    assert Map.new(files, fn {name, data} -> {List.to_string(name), data} end) == %{
             "Série 001.cbz" => big,
             "b.pdf" => "hello",
             "empty.cbr" => ""
           }
  end

  test "stops at the first error from emit", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "a.cbz"), "data")
    entries = ZipStream.plan([{"a.cbz", Path.join(tmp, "a.cbz")}])

    assert {:error, :closed} = ZipStream.write(entries, nil, fn _data, _acc -> {:error, :closed} end)
  end

  test "fails when a file changed size after planning", %{tmp_dir: tmp} do
    path = Path.join(tmp, "a.cbz")
    File.write!(path, "data")
    entries = ZipStream.plan([{"a.cbz", path}])
    File.write!(path, "more data")

    assert {:error, {:file_changed, ^path}} = ZipStream.write(entries, nil, fn _data, acc -> {:ok, acc} end)
  end
end
