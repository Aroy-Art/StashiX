defmodule Stashix.Auth.LoginThrottle do
  @moduledoc """
  Limits password guessing per login name.

  After `@max_failures` failed attempts for a login within `@window_ms`,
  further attempts are refused until the window (counted from the first
  failure) has passed. A successful login clears the count.

  Keyed by login name rather than client address: the app usually sits behind
  a reverse proxy, where the peer address is the proxy's.
  """
  use GenServer

  @table __MODULE__
  @max_failures 10
  @window_ms :timer.minutes(5)
  @sweep_ms :timer.minutes(1)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc "True when `login` has used up its failed attempts for the current window."
  def blocked?(login) do
    case :ets.lookup(@table, key(login)) do
      [{_key, count, started}] -> count >= @max_failures and not expired?(started)
      [] -> false
    end
  end

  def record_failure(login) do
    key = key(login)

    case :ets.lookup(@table, key) do
      [{_key, _count, started}] ->
        if expired?(started),
          do: :ets.insert(@table, {key, 1, now()}),
          else: :ets.update_counter(@table, key, {2, 1})

      [] ->
        :ets.insert(@table, {key, 1, now()})
    end

    :ok
  end

  def clear(login) do
    :ets.delete(@table, key(login))
    :ok
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @window_ms
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  defp key(login), do: login |> String.trim() |> String.downcase()
  defp expired?(started), do: now() - started >= @window_ms
  defp now, do: System.monotonic_time(:millisecond)
end
