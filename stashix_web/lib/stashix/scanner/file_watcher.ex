# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Scanner.FileWatcher do
  use GenServer
  require Logger

  alias Stashix.Library

  @debounce_ms 5_000
  # Calibre libraries sync as a whole once changes stop for this long, so an
  # rsync push (database and files, in any order) lands before the sync.
  @calibre_debounce_ms 30_000
  @sidecar_exts ~w(.jpg .jpeg .png .webp .xml)
  # Events for paths Stashix itself just wrote (metadata write-back) are ignored
  # for this long, so our own writes don't trigger a re-import.
  @suppress_ms 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Ignore file events for `path` for a short while (we are about to write it)."
  def suppress(path) do
    GenServer.cast(__MODULE__, {:suppress, path, System.monotonic_time(:millisecond) + @suppress_ms})
  end

  @doc """
  Whether new and changed files are picked up live: `:watching`, `:idle` (no
  library folders to watch) or `{:disabled, reason}`.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _ -> {:disabled, "The file watcher process is not running."}
  end

  @impl true
  def init(_opts) do
    libraries = load_libraries()
    paths = Enum.map(libraries, & &1.root_path) |> Enum.filter(&File.dir?/1)

    {watcher_pid, status} = if paths != [], do: start_watcher(paths), else: {nil, :idle}

    {:ok,
     %{
       watcher: watcher_pid,
       status: status,
       debounce: %{},
       suppressed: %{},
       libraries: library_path_map(libraries)
     }}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.status, state}

  @impl true
  def handle_cast({:suppress, path, until}, state) do
    now = System.monotonic_time(:millisecond)
    suppressed = state.suppressed |> Map.reject(fn {_, t} -> t < now end) |> Map.put(path, until)
    {:noreply, %{state | suppressed: suppressed}}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    case calibre_library(path, state.libraries) do
      nil -> folder_event(path, events, state)
      library_id -> calibre_event(library_id, path, events, state)
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:trigger_scan_file, path, library_id}, state) do
    Logger.info("FileWatcher triggering scan for #{path}")
    Stashix.Scanner.scan_file(library_id, path)
    {:noreply, %{state | debounce: Map.delete(state.debounce, path)}}
  end

  def handle_info({:trigger_calibre_sync, library_id}, state) do
    Logger.info("FileWatcher: Calibre library #{library_id} changed, syncing")
    Stashix.Scanner.scan_library(library_id)
    {:noreply, %{state | debounce: Map.delete(state.debounce, {:calibre, library_id})}}
  end

  # metadata.db replaced or written, or a book file arrived: (re)start the
  # library's quiet-period timer. Journal and temp files are ignored.
  defp calibre_event(library_id, path, events, state) do
    if interesting_event?(events) and (Path.basename(path) == "metadata.db" or supported_file?(path)) do
      key = {:calibre, library_id}
      {existing_timer, _} = Map.get(state.debounce, key, {nil, nil})
      cancel_timer(existing_timer)
      delay = Application.get_env(:stashix, :calibre_debounce_ms, @calibre_debounce_ms)
      timer = Process.send_after(self(), {:trigger_calibre_sync, library_id}, delay)
      {:noreply, put_in(state, [:debounce, key], {timer, library_id})}
    else
      {:noreply, state}
    end
  end

  defp folder_event(path, events, state) do
    scan_path =
      cond do
        supported_file?(path) -> path
        sidecar_file?(path) -> find_comic_for_sidecar(path)
        true -> nil
      end

    if scan_path && interesting_event?(events) && not suppressed?(state, path) do
      library_id = find_library_id(scan_path, state.libraries)

      if library_id do
        {existing_timer, _} = Map.get(state.debounce, scan_path, {nil, nil})
        cancel_timer(existing_timer)
        timer = Process.send_after(self(), {:trigger_scan_file, scan_path, library_id}, @debounce_ms)
        {:noreply, put_in(state, [:debounce, scan_path], {timer, library_id})}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # FileSystem returns :ignore when its backend (inotify-tools on Linux) is
  # missing. Run without live watching rather than taking the app down;
  # a manual library scan still picks up changes.
  defp start_watcher(paths) do
    case FileSystem.start_link(dirs: paths) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        {pid, :watching}

      other ->
        Logger.warning("FileWatcher: live watching disabled, file system watcher did not start: #{inspect(other)}")
        {nil, {:disabled, disabled_reason()}}
    end
  end

  defp disabled_reason do
    case :os.type() do
      {:unix, :linux} -> "The file system watcher could not start. It needs inotify-tools, which isn't installed."
      _ -> "The file system watcher could not start on this system. The server log has the details."
    end
  end

  defp load_libraries do
    try do
      Library.list_libraries(%{role: :admin})
    rescue
      _ -> []
    end
  end

  defp library_path_map(libraries) do
    Map.new(libraries, fn lib -> {lib.root_path, {lib.id, lib.source}} end)
  end

  defp suppressed?(state, path) do
    case Map.get(state.suppressed, path) do
      nil -> false
      until -> System.monotonic_time(:millisecond) < until
    end
  end

  defp supported_file?(path), do: Stashix.Media.Formats.supported?(path)

  defp sidecar_file?(path) do
    String.downcase(Path.extname(path)) in @sidecar_exts
  end

  defp find_comic_for_sidecar(sidecar_path) do
    base = Stashix.Metadata.Sidecar.stem(sidecar_path)

    Enum.find_value(Stashix.Media.Formats.extensions(), fn ext ->
      candidate = base <> ext
      if File.exists?(candidate), do: candidate
    end)
  end

  defp interesting_event?(events) do
    Enum.any?(events, &(&1 in [:created, :modified, :moved_to]))
  end

  defp find_library_id(path, libraries) do
    Enum.find_value(libraries, fn {root, {id, _source}} ->
      if inside?(path, root), do: id
    end)
  end

  defp calibre_library(path, libraries) do
    Enum.find_value(libraries, fn {root, {id, source}} ->
      if source == :calibre and inside?(path, root), do: id
    end)
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
