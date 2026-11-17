# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.PageCache do
  @moduledoc """
  Remembers each book file's page list, so serving a page doesn't list the
  whole archive (or run `pdfinfo`) again.

  Entries are keyed by path and checked against the file's mtime, size and
  inode on every lookup: a rescanned, replaced or rewritten file simply
  misses and is listed afresh, with no explicit invalidation. Errors are not
  cached. Entries unused for `@idle_ms` are swept.
  """
  use GenServer

  @table __MODULE__
  @idle_ms :timer.minutes(30)
  @sweep_ms :timer.minutes(5)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc """
  The cached page list for `path`, computing it with `fun` when absent or the
  file changed. Without the table (cache not started) it just calls `fun`.
  """
  @spec fetch(Path.t(), (-> {:ok, [String.t()]} | {:error, term()})) :: {:ok, [String.t()]} | {:error, term()}
  def fetch(path, fun) do
    with true <- :ets.whereis(@table) != :undefined,
         {:ok, stamp} <- stamp(path) do
      case :ets.lookup(@table, path) do
        [{^path, ^stamp, pages, _used}] ->
          :ets.update_element(@table, path, {4, now()})
          {:ok, pages}

        _ ->
          store(path, stamp, fun.())
      end
    else
      _ -> fun.()
    end
  end

  @doc "Drops the entry for `path`."
  def delete(path) do
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, path)
    :ok
  end

  defp store(path, stamp, {:ok, pages} = result) do
    :ets.insert(@table, {path, stamp, pages, now()})
    result
  end

  defp store(_path, _stamp, error), do: error

  # Inode catches an atomic replace (rename over the file) within the same
  # second, which mtime alone would miss.
  defp stamp(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size, inode: inode}} -> {:ok, {mtime, size, inode}}
      error -> error
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @idle_ms
    :ets.select_delete(@table, [{{:_, :_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
