# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.RenderCacheTest do
  # Not async: points the app-wide cache dir at this test's directory.
  use ExUnit.Case, async: false

  alias Stashix.Media.RenderCache

  setup do
    tmp = Path.join(System.tmp_dir!(), "render_cache_test_#{:erlang.unique_integer([:positive])}")
    cache = Path.join(tmp, "cache")
    File.mkdir_p!(tmp)

    old = Application.get_env(:stashix, :page_cache_dir)
    Application.put_env(:stashix, :page_cache_dir, cache)

    on_exit(fn ->
      Application.put_env(:stashix, :page_cache_dir, old)
      File.rm_rf!(tmp)
    end)

    source = Path.join(tmp, "book.pdf")
    File.write!(source, "pdf")
    %{source: source, cache: cache}
  end

  defp counting(result) do
    counter = :counters.new(1, [])
    {fn -> :counters.add(counter, 1, 1) && result end, fn -> :counters.get(counter, 1) end}
  end

  test "renders once, then serves from disk", %{source: source} do
    {fun, calls} = counting({:ok, "jpeg"})

    assert {:ok, "jpeg"} = RenderCache.fetch(source, "p1-w800", fun)
    assert {:ok, "jpeg"} = RenderCache.fetch(source, "p1-w800", fun)
    assert calls.() == 1
  end

  test "variants are cached apart", %{source: source} do
    assert {:ok, "a"} = RenderCache.fetch(source, "p1-w800", fn -> {:ok, "a"} end)
    assert {:ok, "b"} = RenderCache.fetch(source, "p1-w1200", fn -> {:ok, "b"} end)
    assert {:ok, "a"} = RenderCache.fetch(source, "p1-w800", fn -> {:ok, "x"} end)
  end

  test "a changed source misses", %{source: source} do
    assert {:ok, "old"} = RenderCache.fetch(source, "p1-w800", fn -> {:ok, "old"} end)
    File.write!(source, "a longer pdf")
    assert {:ok, "new"} = RenderCache.fetch(source, "p1-w800", fn -> {:ok, "new"} end)
  end

  test "errors are not cached", %{source: source} do
    {fun, calls} = counting({:error, :boom})

    assert {:error, :boom} = RenderCache.fetch(source, "p1-w800", fun)
    assert {:error, :boom} = RenderCache.fetch(source, "p1-w800", fun)
    assert calls.() == 2
  end

  test "prune/0 drops renders unused for two weeks", %{source: source, cache: cache} do
    RenderCache.fetch(source, "p1-w800", fn -> {:ok, "old"} end)
    RenderCache.fetch(source, "p2-w800", fn -> {:ok, "fresh"} end)

    [old | _] = cache |> Path.join("*-p1-w800.jpg") |> Path.wildcard()
    File.touch!(old, System.os_time(:second) - 15 * 86_400)

    assert RenderCache.prune() == 1
    assert [_fresh] = Path.wildcard(Path.join(cache, "*.jpg"))
  end
end
