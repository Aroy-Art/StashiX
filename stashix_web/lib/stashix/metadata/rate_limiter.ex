defmodule Stashix.Metadata.RateLimiter do
  @moduledoc """
  Per-source request limiter (GCRA / leaky bucket).

  `reserve/3` books the next slot for a source and returns how long the caller
  must wait before sending. When the wait would exceed `max_wait` nothing is
  booked and `{:error, {:rate_limited, ms}}` is returned so the job can snooze.
  """
  use GenServer

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Blocks until a request slot is free. `limit` is `{requests, per_ms}`."
  def acquire(key, limit, max_wait \\ 30_000) do
    case GenServer.call(__MODULE__, {:reserve, key, limit, max_wait}) do
      {:ok, 0} ->
        :ok

      {:ok, wait} ->
        Process.sleep(wait)
        :ok

      {:error, wait} ->
        {:error, {:rate_limited, wait}}
    end
  end

  @doc "Forget state for a source (e.g. after its limit changed)."
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
  def handle_cast({:reset, key}, state), do: {:noreply, Map.delete(state, key)}
end
