# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.PageCacheTest do
  use ExUnit.Case, async: true

  alias Stashix.Media.{Extractor, PageCache}

  setup do
    tmp = Path.join(System.tmp_dir!(), "page_cache_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{path: Path.join(tmp, "book.cbz")}
  end

  # Counts calls, so a test can tell a hit from a miss.
  defp counting(result) do
    counter = :counters.new(1, [])
    {fn -> :counters.add(counter, 1, 1) && result end, fn -> :counters.get(counter, 1) end}
  end

  test "lists once while the file is unchanged", %{path: path} do
    File.write!(path, "x")
    {fun, calls} = counting({:ok, ["001.jpg"]})

    assert {:ok, ["001.jpg"]} = PageCache.fetch(path, fun)
    assert {:ok, ["001.jpg"]} = PageCache.fetch(path, fun)
    assert calls.() == 1
  end

  test "a replaced file is listed again", %{path: path} do
    File.write!(path, "x")
    assert {:ok, ["old.jpg"]} = PageCache.fetch(path, fn -> {:ok, ["old.jpg"]} end)

    # Same size and (likely) same second: only the inode tells them apart.
    tmp = path <> ".new"
    File.write!(tmp, "y")
    File.rename!(tmp, path)

    assert {:ok, ["new.jpg"]} = PageCache.fetch(path, fn -> {:ok, ["new.jpg"]} end)
  end

  test "errors are not cached", %{path: path} do
    File.write!(path, "x")
    {fun, calls} = counting({:error, :boom})

    assert {:error, :boom} = PageCache.fetch(path, fun)
    assert {:error, :boom} = PageCache.fetch(path, fun)
    assert calls.() == 2
  end

  test "a missing file goes straight to the listing", %{path: path} do
    assert {:error, :enoent} = PageCache.fetch(path, fn -> {:error, :enoent} end)
  end

  test "delete/1 forgets the entry", %{path: path} do
    File.write!(path, "x")
    {fun, calls} = counting({:ok, []})

    PageCache.fetch(path, fun)
    PageCache.delete(path)
    PageCache.fetch(path, fun)
    assert calls.() == 2
  end

  test "Extractor.get_page/2 serves from the cached list", %{path: path} do
    {:ok, _} = :zip.create(String.to_charlist(path), [{~c"001.jpg", "one"}, {~c"002.jpg", "two"}])

    assert {:ok, ["001.jpg", "002.jpg"]} = Extractor.cached_pages(path)
    assert {:ok, "two"} = Extractor.get_page(path, 1)
  end
end
