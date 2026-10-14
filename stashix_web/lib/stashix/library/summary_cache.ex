defmodule Stashix.Library.SummaryCache do
  @moduledoc """
  Short-lived cache for the library summary numbers (book, issue and series
  counts, total file size) shown on the home and library pages.

  Every page load runs these twice (dead render, then the LiveView mount), and
  they rarely change between loads. Entries live for `@ttl_ms`; the scanner and
  the trash actions clear the cache when they change what is counted, so the
  TTL only bounds staleness for rarer edits.

  Disabled when `:ttl_ms` is configured as 0 (the test env), so sandboxed tests
  never see each other's numbers.
  """
  use GenServer

  @table __MODULE__
  @default_ttl_ms :timer.seconds(30)
  @sweep_ms :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Returns the cached value for `key`, computing it with `fun` when absent or expired."
  def fetch(key, fun) do
    case ttl_ms() do
      0 -> fun.()
      ttl -> lookup(key) || store(key, fun.(), ttl)
    end
  end

  @doc "Drops every entry. Called after writes that change what the summaries count."
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{_key, value, expires}] -> if expires > now(), do: value
      [] -> nil
    end
  end

  defp store(key, value, ttl) do
    :ets.insert(@table, {key, value, now() + ttl})
    value
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now()}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  defp ttl_ms, do: Application.get_env(:stashix, __MODULE__, [])[:ttl_ms] || @default_ttl_ms
  defp now, do: System.monotonic_time(:millisecond)
end
