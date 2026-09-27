defmodule Stashix.Metadata.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.RateLimiter

  test "allows a burst up to the limit, then asks callers to wait" do
    key = "test-#{System.unique_integer()}"

    for _ <- 1..3, do: assert(RateLimiter.acquire(key, {3, 60_000}, 0) == :ok)
    assert {:error, {:rate_limited, wait}} = RateLimiter.acquire(key, {3, 60_000}, 0)
    assert wait > 19_000 and wait <= 20_000
  end

  test "short waits block instead of failing" do
    key = "test-#{System.unique_integer()}"
    assert RateLimiter.acquire(key, {1, 50}, 1_000) == :ok
    {us, :ok} = :timer.tc(fn -> RateLimiter.acquire(key, {1, 50}, 1_000) end)
    assert us >= 30_000
  end
end
