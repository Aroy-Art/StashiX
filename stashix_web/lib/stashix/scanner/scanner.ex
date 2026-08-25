defmodule Stashix.Scanner do
  use GenServer
  require Logger

  alias Stashix.Library
  alias Stashix.Media.Thumbnail
  alias Stashix.Metadata.Parser

  @supported_formats ~w(.cbz .cbr .cb7 .epub .pdf)
  @ets_table :scan_tasks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def scan_library(library_id, force \\ false) do
    GenServer.cast(__MODULE__, {:scan, library_id, force})
  end

  def get_task_status(library_id) do
    case :ets.lookup(@ets_table, library_id) do
      [{^library_id, status}] -> status
      [] -> nil
    end
  end

  def list_active_tasks do
    :ets.tab2list(@ets_table)
    |> Enum.map(fn {id, status} -> Map.put(status, :library_id, id) end)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@ets_table, [:named_table, :public, :set])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:scan, library_id, force}, state) do
    Task.start(fn -> do_scan(library_id, force) end)
    {:noreply, state}
  end

  defp do_scan(library_id, force) do
    library = Library.get_library!(library_id)

    Logger.info("Starting scan for library #{library.name} at #{library.root_path}")

    files = collect_files(library.root_path)
    total = length(files)

    update_task_status(library_id, %{scanned: 0, total: total, done: false})
    broadcast_progress(library_id, 0, total)

    files
    |> Enum.with_index(1)
    |> Enum.each(fn {file_path, idx} ->
      process_file(file_path, library, force)
      update_task_status(library_id, %{scanned: idx, total: total, done: false})
      broadcast_progress(library_id, idx, total)
    end)

    Library.update_series_counts(library_id)

    update_task_status(library_id, %{scanned: total, total: total, done: true})
    broadcast_progress(library_id, total, total)

    Logger.info("Scan complete for library #{library.name}: #{total} files processed")
  end

  defp collect_files(root_path) do
    case File.ls(root_path) do
      {:ok, _} ->
        Path.wildcard(Path.join([root_path, "**", "*"]))
        |> Enum.filter(fn path ->
          File.regular?(path) &&
            String.downcase(Path.extname(path)) in @supported_formats
        end)

      {:error, reason} ->
        Logger.error("Cannot access library path #{root_path}: #{inspect(reason)}")
        []
    end
  end

  defp process_file(file_path, library, force) do
    stat = File.stat!(file_path)
    file_hash = compute_hash(file_path, stat.size)
    last_modified = stat.mtime |> NaiveDateTime.from_erl!()

    case Library.get_book_by_path(file_path) do
      nil ->
        case Library.get_book_by_hash(file_hash) do
          nil ->
            import_new_book(file_path, library, file_hash, last_modified, stat.size)

          existing_book ->
            Library.update_book(existing_book, %{path: file_path})
        end

      existing_book ->
        if force || NaiveDateTime.compare(last_modified, existing_book.last_modified || ~N[1970-01-01 00:00:00]) == :gt do
          reimport_book(existing_book, file_path, library, file_hash, last_modified, stat.size)
        end
    end
  end

  defp import_new_book(file_path, library, file_hash, last_modified, file_size) do
    filename = Path.basename(file_path, Path.extname(file_path))
    parsed = Parser.parse_filename(filename)
    comicinfo = Parser.parse_comicinfo(file_path)
    metadata = Map.merge(parsed, comicinfo)

    series = find_or_create_series(file_path, library, metadata)

    format = file_path |> Path.extname() |> String.downcase() |> String.trim_leading(".") |> String.to_atom()

    book_attrs = %{
      library_id: library.id,
      series_id: series && series.id,
      path: file_path,
      title: Map.get(metadata, :title) || filename,
      format: format,
      issue_number: Map.get(metadata, :issue_number),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      page_count: Map.get(metadata, :page_count, 0),
      language: Map.get(metadata, :language, "en"),
      summary: Map.get(metadata, :summary),
      file_hash: file_hash,
      file_size: file_size,
      last_modified: last_modified
    }

    case Library.create_book(book_attrs) do
      {:ok, book} ->
        generate_thumbnail(book, file_path)
        Phoenix.PubSub.broadcast(Stashix.PubSub, "scan:#{library.id}", {:book_added, book})

      {:error, reason} ->
        Logger.error("Failed to import #{file_path}: #{inspect(reason)}")
    end
  end

  defp reimport_book(book, file_path, _library, file_hash, last_modified, file_size) do
    filename = Path.basename(file_path, Path.extname(file_path))
    parsed = Parser.parse_filename(filename)
    comicinfo = Parser.parse_comicinfo(file_path)
    metadata = Map.merge(parsed, comicinfo)

    attrs = %{
      page_count: Map.get(metadata, :page_count, book.page_count),
      language: Map.get(metadata, :language, book.language),
      summary: Map.get(metadata, :summary, book.summary),
      file_hash: file_hash,
      file_size: file_size,
      last_modified: last_modified
    }

    case Library.update_book(book, attrs) do
      {:ok, updated_book} -> generate_thumbnail(updated_book, file_path)
      {:error, reason} -> Logger.error("Failed to reimport #{file_path}: #{inspect(reason)}")
    end
  end

  defp find_or_create_series(file_path, library, metadata) do
    series_name = Map.get(metadata, :series)
    parent_dir = Path.dirname(file_path)
    dir_name = Path.basename(parent_dir)

    name =
      cond do
        series_name && series_name != "" -> series_name
        dir_name != Path.basename(library.root_path) -> dir_name
        true -> nil
      end

    if name do
      case Library.create_or_find_series(%{
             library_id: library.id,
             name: name,
             path: parent_dir,
             volume: Map.get(metadata, :volume)
           }) do
        {:ok, series} -> series
        _ -> nil
      end
    end
  end

  defp generate_thumbnail(book, file_path) do
    thumb_dir = Application.get_env(:stashix, :thumbnail_dir, "/tmp/stashix/thumbnails")
    File.mkdir_p!(thumb_dir)
    dest = Path.join(thumb_dir, "#{book.id}.jpg")

    case Thumbnail.generate(file_path, dest) do
      {:ok, _} -> Library.create_or_update_cover(book.id, dest)
      {:error, reason} -> Logger.warning("Thumbnail failed for #{file_path}: #{inspect(reason)}")
    end
  end

  defp compute_hash(file_path, file_size) do
    prefix = "#{file_size}:"

    case File.open(file_path, [:read, :binary]) do
      {:ok, file} ->
        chunk = IO.binread(file, 65536)
        File.close(file)
        hash = :crypto.hash(:sha256, chunk) |> Base.encode16(case: :lower)
        prefix <> hash

      {:error, _} ->
        prefix <> "unknown"
    end
  end

  defp update_task_status(library_id, status) do
    :ets.insert(@ets_table, {library_id, status})
  end

  defp broadcast_progress(library_id, scanned, total) do
    Phoenix.PubSub.broadcast(
      Stashix.PubSub,
      "scan:#{library_id}",
      {:scan_progress, %{library_id: library_id, scanned: scanned, total: total}}
    )
  end
end
