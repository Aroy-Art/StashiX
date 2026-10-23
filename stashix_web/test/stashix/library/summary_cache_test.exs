# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.SummaryCacheTest do
  # Changes the global cache config, so not async.
  use ExUnit.Case, async: false

  alias Stashix.Library.SummaryCache

  setup do
    previous = Application.get_env(:stashix, SummaryCache)
    Application.put_env(:stashix, SummaryCache, ttl_ms: 50)
    SummaryCache.clear()

    on_exit(fn ->
      SummaryCache.clear()
      Application.put_env(:stashix, SummaryCache, previous)
    end)
  end

  defp counting_fun do
    counter = :counters.new(1, [])
    fun = fn -> :counters.add(counter, 1, 1) && :counters.get(counter, 1) end
    {fun, fn -> :counters.get(counter, 1) end}
  end

  test "computes once and serves the cached value while fresh" do
    {fun, calls} = counting_fun()

    assert SummaryCache.fetch(:key, fun) == 1
    assert SummaryCache.fetch(:key, fun) == 1
    assert calls.() == 1
  end

  test "recomputes after the TTL" do
    {fun, calls} = counting_fun()

    SummaryCache.fetch(:key, fun)
    Process.sleep(60)

    assert SummaryCache.fetch(:key, fun) == 2
    assert calls.() == 2
  end

  test "clear drops cached values" do
    {fun, calls} = counting_fun()

    SummaryCache.fetch(:key, fun)
    SummaryCache.clear()
    SummaryCache.fetch(:key, fun)

    assert calls.() == 2
  end

  test "a TTL of 0 bypasses the cache" do
    Application.put_env(:stashix, SummaryCache, ttl_ms: 0)
    {fun, calls} = counting_fun()

    SummaryCache.fetch(:key, fun)
    SummaryCache.fetch(:key, fun)

    assert calls.() == 2
  end
end
