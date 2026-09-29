defmodule Stashix.Metadata.RateLimiter do
  @moduledoc """
  Per-source request limiter (GCRA / leaky bucket).

  `reserve/3` books the next slot for a source and returns how long the caller
  must wait before sending. When the wait would exceed `max_wait` nothing is
  booked and `{:error, {:rate_limited, ms}}` is returned so the job can snooze.

  A process can register a callback with `on_wait/1`; it is called with the
  wait in ms and the limit that caused it before the process sleeps (used to show progress in the UI).
  """
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Blocks until a request slot is free. `limit` is `{requests, per_ms}`."
  def acquire(key, limit, max_wait \\ 30_000) do
    case GenServer.call(__MODULE__, {:reserve, key, limit, max_wait}) do
      {:ok, 0} ->
        :ok

      {:ok, wait} ->
        if fun = Process.get({__MODULE__, :on_wait}), do: fun.(wait, limit)
        Process.sleep(wait)
        :ok

      {:error, wait} ->
        {:error, {:rate_limited, wait}}
    end
  end

  @doc "Calls `fun.(wait_ms, limit)` whenever this process has to wait for a slot."
  def on_wait(fun) when is_function(fun, 2), do: Process.put({__MODULE__, :on_wait}, fun)

  @doc "Forget state for a source and its endpoints (e.g. after a limit changed)."
  def reset(key), do: GenServer.cast(__MODULE__, {:reset, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:reserve, key, {n, per_ms}, max_wait}, _from, state) do
    now = System.monotonic_time(:millisecond)
    interval = per_ms / n
    tat = max(Map.get(state, key, now), now)
    allow_at = tat - (per_ms - interval)
    wait = max(0, ceil(allow_at - now))

    if wait > max_wait do
      {:reply, {:error, wait}, state}
    else
      {:reply, {:ok, wait}, Map.put(state, key, tat + interval)}
    end
  end

  @impl true
  def handle_cast({:reset, key}, state),
    do: {:noreply, Map.reject(state, fn {k, _} -> k == key or String.starts_with?(k, key <> ":") end)}
end
