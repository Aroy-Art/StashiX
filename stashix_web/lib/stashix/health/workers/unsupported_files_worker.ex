defmodule Stashix.Health.Workers.UnsupportedFilesWorker do
  @moduledoc "Walks a library root path and records files with unsupported extensions."
  use Oban.Worker,
    queue: :health,
    max_attempts: 2,
    unique: [keys: [:library_id], states: [:available, :scheduled, :executing]]

  alias Stashix.Repo
  alias Stashix.Library.Library
  alias Stashix.Health

  @supported ~w(.cbz .cbr .cb7 .epub .pdf)

  # Extensions to silently ignore — metadata and sidecar files that are never
  # content and would flood results if shown.
  @ignored ~w(.xml .jpg .jpeg .png .webp .gif .nfo .txt .db .ini .bak .opf .ds_store)

  @impl true
  def perform(%Oban.Job{args: %{"library_id" => library_id}}) do
    case Repo.get(Library, library_id) do
      nil ->
        {:cancel, :not_found}

      %Library{root_path: root_path} ->
        Health.clear_unsupported_file_results(library_id)
        Health.broadcast(library_id, {:unsupported_scan_started, %{library_id: library_id}})

        unsupported = collect_unsupported(root_path)

        Enum.each(unsupported, fn path ->
          Health.upsert_unsupported_file(library_id, path)
        end)

        Health.broadcast(library_id, {:unsupported_scan_done, %{library_id: library_id, count: length(unsupported)}})
        :ok
    end
  end

  defp collect_unsupported(root_path) do
    case File.ls(root_path) do
      {:ok, _} -> walk([root_path], [])
      {:error, _} -> []
    end
  end

  defp walk([], acc), do: acc

  defp walk(dirs, acc) do
    {next_dirs, found} =
      Enum.reduce(dirs, {[], acc}, fn dir, {subdirs, files} ->
        case File.ls(dir) do
          {:ok, entries} ->
            entries
            |> Enum.map(&Path.join(dir, &1))
            |> Enum.reduce({subdirs, files}, fn path, {sd, fl} ->
              cond do
                File.dir?(path) -> {[path | sd], fl}
                unsupported?(path) -> {sd, [path | fl]}
                true -> {sd, fl}
              end
            end)

          _ ->
            {subdirs, files}
        end
      end)

    walk(next_dirs, found)
  end

  defp unsupported?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext not in @supported and ext not in @ignored and ext != ""
  end
end
