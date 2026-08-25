defmodule Stashix.Scanner.FileWatcher do
  use GenServer
  require Logger

  alias Stashix.Library

  @debounce_ms 5_000
  @supported_exts ~w(.cbz .cbr .cb7 .epub .pdf)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    libraries = load_libraries()
    paths = Enum.map(libraries, & &1.root_path) |> Enum.filter(&File.dir?/1)

    watcher_pid =
      if paths != [] do
        {:ok, pid} = FileSystem.start_link(dirs: paths)
        FileSystem.subscribe(pid)
        pid
      end

    {:ok, %{watcher: watcher_pid, debounce: %{}, libraries: library_path_map(libraries)}}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    if supported_file?(path) && interesting_event?(events) do
      library_id = find_library_id(path, state.libraries)

      if library_id do
        cancel_timer(state.debounce[library_id])
        timer = Process.send_after(self(), {:trigger_scan, library_id}, @debounce_ms)
        {:noreply, put_in(state, [:debounce, library_id], timer)}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:trigger_scan, library_id}, state) do
    Logger.info("FileWatcher triggering scan for library #{library_id}")
    Stashix.Scanner.scan_library(library_id)
    {:noreply, put_in(state, [:debounce, library_id], nil)}
  end

  defp load_libraries do
    try do
      Library.list_libraries(%{role: :admin})
    rescue
      _ -> []
    end
  end

  defp library_path_map(libraries) do
    Map.new(libraries, fn lib -> {lib.root_path, lib.id} end)
  end

  defp supported_file?(path) do
    String.downcase(Path.extname(path)) in @supported_exts
  end

  defp interesting_event?(events) do
    Enum.any?(events, &(&1 in [:created, :modified, :moved_to]))
  end

  defp find_library_id(path, libraries) do
    Enum.find_value(libraries, fn {root, id} ->
      if String.starts_with?(path, root), do: id
    end)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)
end
