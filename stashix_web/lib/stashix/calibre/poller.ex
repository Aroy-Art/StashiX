# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Calibre.Poller do
  @moduledoc """
  The file watcher's fallback for Calibre libraries (D10): every few minutes,
  compares each Calibre library's `metadata.db` stamp with the one last
  synced and queues a sync when it moved, or when the last sync found files
  missing (they may have arrived since). Catches what inotify can't see:
  changes while Stashix was down, bind mounts, missed events.

  `config :stashix, calibre_poll_ms: nil` turns it off (tests).
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Stashix.Calibre.Snapshot
  alias Stashix.Library.Library
  alias Stashix.Repo

  @default_ms 300_000
  # The first check comes soon after boot, to catch changes made while down.
  @first_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    if interval(), do: Process.send_after(self(), :poll, min(@first_ms, interval()))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:poll, state) do
    try do
      Enum.each(stale_libraries(), &Stashix.Scanner.scan_library/1)
    rescue
      e -> Logger.warning("Calibre poll failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :poll, interval())
    {:noreply, state}
  end

  @doc "Ids of Calibre libraries whose database changed since the last sync, or that wait on files."
  def stale_libraries do
    from(l in Library, where: l.source == :calibre, select: {l.id, l.root_path, l.calibre_state})
    |> Repo.all()
    |> Enum.filter(fn {_id, root, state} -> stale?(root, state || %{}) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp stale?(root, state) do
    case Snapshot.stamp(root) do
      {:ok, stamp} ->
        synced = Map.new(state["stamp"] || %{}, fn {k, v} -> {to_string(k), v} end)
        current = Map.new(stamp, fn {k, v} -> {to_string(k), v} end)
        synced != current or get_in(state, ["summary", "missing_files"]) not in [nil, 0]

      # Calibre is writing; the next poll sees it.
      {:error, :busy} ->
        false

      # No database (yet): report it through a sync, once.
      {:error, _} ->
        state["error"] == nil
    end
  end

  defp interval, do: Application.get_env(:stashix, :calibre_poll_ms, @default_ms)
end
