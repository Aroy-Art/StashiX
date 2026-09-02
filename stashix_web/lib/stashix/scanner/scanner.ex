defmodule Stashix.Scanner do
  use GenServer
  require Logger

  alias Stashix.Library
  alias Stashix.Media.{Thumbnail, Extractor}
  alias Stashix.Metadata.Parser

  @supported_formats ~w(.cbz .cbr .cb7 .epub .pdf)
  @ets_table :scan_tasks
  @metadata_concurrency 4
  @thumbnail_concurrency 4

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def scan_library(library_id, force \\ false) do
    GenServer.cast(__MODULE__, {:scan, library_id, force})
  end

  def scan_file(library_id, file_path) do
    GenServer.cast(__MODULE__, {:scan_file, library_id, file_path})
  end

  def scan_series(series_id, force \\ false) do
    GenServer.cast(__MODULE__, {:scan_series, series_id, force})
  end

  @doc false
  def scan_sync(library_id, force \\ false), do: do_scan(library_id, force)

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
    Task.Supervisor.start_child(Stashix.Scanner.TaskSupervisor, fn ->
      do_scan(library_id, force)
    end)

    {:noreply, state}
  end

  def handle_cast({:scan_file, library_id, file_path}, state) do
    Task.Supervisor.start_child(Stashix.Scanner.TaskSupervisor, fn ->
      do_scan_file(library_id, file_path)
    end)

    {:noreply, state}
  end

  def handle_cast({:scan_series, series_id, force}, state) do
    Task.Supervisor.start_child(Stashix.Scanner.TaskSupervisor, fn ->
      do_scan_series(series_id, force)
    end)

    {:noreply, state}
  end

  defp do_scan(library_id, force) do
    library = Library.get_library!(library_id)
    Logger.info("Starting scan for library #{library.name} at #{library.root_path}")

    update_task_status(library_id, %{scanned: 0, total: 0, done: false, collecting: true})
    broadcast_progress(library_id, 0, 0)

    files = collect_files(library.root_path)
    total = length(files)

    update_task_status(library_id, %{scanned: 0, total: total, done: false, collecting: false})
    broadcast_progress(library_id, 0, total)

    # Pre-warm series cache and books cache: bulk queries instead of N round-trips
    series_cache = Library.load_series_cache(library_id)
    books_cache = if force, do: %{}, else: Library.load_books_cache(library_id)

    # Partition: files that need full parse vs unchanged (skip Stage 1 for those)
    {files_to_parse, files_unchanged} =
      Enum.split_with(files, fn path ->
        case Map.get(books_cache, path) do
          nil -> true
          %{deleted_at: da} when not is_nil(da) -> true
          %{last_modified: lm} ->
            case File.stat(path) do
              {:ok, stat} -> NaiveDateTime.from_erl!(stat.mtime) != lm
              _ -> true
            end
        end
      end)

    unchanged_count = length(files_unchanged)
    Logger.info("[scan] #{unchanged_count} unchanged, #{length(files_to_parse)} need parse")
    broadcast_progress(library_id, unchanged_count, total)

    # Stage 1: Parse metadata concurrently (hash + filename + comicinfo) — only changed files
    parsed_files =
      files_to_parse
      |> Task.async_stream(&parse_file_metadata/1,
           max_concurrency: @metadata_concurrency,
           ordered: true,
           timeout: 60_000)
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        {:exit, reason} ->
          Logger.error("Metadata parse crashed: #{inspect(reason)}")
          []
      end)

    # Stage 2: DB upserts serially (prevents series creation races, uses cache)
    # Unchanged files count as already scanned
    {thumbnail_jobs, _cache} =
      parsed_files
      |> Enum.with_index(unchanged_count + 1)
      |> Enum.reduce({[], series_cache}, fn {file_meta, idx}, {jobs, cache} ->
        {job, new_cache} = upsert_book(file_meta, library, force, cache)
        update_task_status(library_id, %{scanned: idx, total: total, done: false})
        broadcast_progress(library_id, idx, total)
        new_jobs = if job, do: [job | jobs], else: jobs
        {new_jobs, new_cache}
      end)

    # Stage 3: Generate thumbnails concurrently
    thumb_total = length(thumbnail_jobs)
    if thumb_total > 0 do
      broadcast_progress(library_id, 0, thumb_total, false, :thumbnails)
    end
    {:ok, thumb_counter} = Agent.start_link(fn -> 0 end)

    thumbnail_jobs
    |> Task.async_stream(
      fn {book, path} ->
        result = generate_thumbnail(book, path)
        n = Agent.get_and_update(thumb_counter, fn c -> {c + 1, c + 1} end)
        broadcast_progress(library_id, n, thumb_total, false, :thumbnails)
        result
      end,
      max_concurrency: @thumbnail_concurrency,
      ordered: false,
      timeout: 120_000
    )
    |> Stream.run()

    Agent.stop(thumb_counter)

    if File.dir?(library.root_path) do
      Library.mark_orphaned_books(library_id, files)
      Library.mark_empty_series_deleted(library_id)
    end

    Library.update_series_counts(library_id)

    update_task_status(library_id, %{scanned: total, total: total, done: true})
    broadcast_progress(library_id, total, total, true)

    Logger.info("Scan complete for library #{library.name}: #{total} files processed")
  end

  defp parse_file_metadata(file_path) do
    stat = File.stat!(file_path)
    file_hash = compute_hash(file_path, stat.size)
    last_modified = NaiveDateTime.from_erl!(stat.mtime)
    filename = Path.basename(file_path, Path.extname(file_path))
    parsed = Parser.parse_filename(filename)
    comicinfo = Parser.parse_comicinfo(file_path)

    %{
      file_path: file_path,
      file_hash: file_hash,
      last_modified: last_modified,
      file_size: stat.size,
      parsed: parsed,
      comicinfo: comicinfo,
      metadata: Map.merge(parsed, comicinfo)
    }
  end

  defp upsert_book(
         %{file_path: file_path, file_hash: file_hash, last_modified: last_modified} = file_meta,
         library,
         force,
         cache
       ) do
    case Library.get_book_by_path(file_path) do
      nil ->
        case Library.get_book_by_hash(file_hash) do
          nil -> create_book_from_meta(file_meta, library, cache)
          existing -> update_book_from_meta(existing, file_meta, library, cache)
        end

      existing ->
        was_deleted = existing.deleted_at != nil

        modified =
          NaiveDateTime.compare(
            last_modified,
            existing.last_modified || ~N[1970-01-01 00:00:00]
          ) == :gt

        if force || was_deleted || modified do
          update_book_from_meta(existing, file_meta, library, cache)
        else
          {nil, cache}
        end
    end
  end

  defp create_book_from_meta(
         %{
           file_path: file_path,
           file_hash: file_hash,
           last_modified: last_modified,
           file_size: file_size,
           parsed: parsed,
           comicinfo: comicinfo,
           metadata: metadata
         },
         library,
         cache
       ) do
    {series, new_cache} = find_or_create_series_cached(file_path, library, cache)
    filename = Path.basename(file_path, Path.extname(file_path))
    format = file_path |> Path.extname() |> String.downcase() |> String.trim_leading(".") |> String.to_atom()

    attrs = %{
      library_id: library.id,
      series_id: series && series.id,
      path: file_path,
      title: Map.get(metadata, :title) || filename,
      format: format,
      type: if(series, do: "issue", else: "standalone"),
      issue_number: if(series, do: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      page_count: resolve_page_count(metadata, file_path, 0),
      language: Map.get(metadata, :language, "en"),
      summary: Map.get(metadata, :summary),
      source_format: Map.get(parsed, :source_format),
      file_hash: file_hash,
      file_size: file_size,
      last_modified: last_modified
    }

    case Library.create_book(attrs) do
      {:ok, book} ->
        Phoenix.PubSub.broadcast(Stashix.PubSub, "scan:#{library.id}", {:book_added, book})
        {{book, file_path}, new_cache}

      {:error, reason} ->
        Logger.error("Failed to import #{file_path}: #{inspect(reason)}")
        {nil, new_cache}
    end
  end

  defp update_book_from_meta(
         book,
         %{
           file_path: file_path,
           file_hash: file_hash,
           last_modified: last_modified,
           file_size: file_size,
           parsed: parsed,
           comicinfo: comicinfo,
           metadata: metadata
         },
         library,
         cache
       ) do
    {series, new_cache} = find_or_create_series_cached(file_path, library, cache)
    filename = Path.basename(file_path, Path.extname(file_path))

    attrs = %{
      path: file_path,
      title: Map.get(metadata, :title) || filename,
      issue_number: if(series, do: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      series_id: series && series.id,
      type: if(series, do: "issue", else: "standalone"),
      page_count: resolve_page_count(metadata, file_path, book.page_count),
      language: Map.get(metadata, :language, book.language),
      summary: Map.get(metadata, :summary, book.summary),
      source_format: Map.get(parsed, :source_format),
      file_hash: file_hash,
      file_size: file_size,
      last_modified: last_modified,
      deleted_at: nil
    }

    case Library.update_book(book, attrs) do
      {:ok, updated_book} -> {{updated_book, file_path}, new_cache}
      {:error, reason} ->
        Logger.error("Failed to reimport #{file_path}: #{inspect(reason)}")
        {nil, new_cache}
    end
  end

  @default_standalone_patterns ["one-shot", "one shot", "oneshot"]

  defp find_or_create_series_cached(file_path, library, cache) do
    parent_dir = Path.dirname(file_path)
    dir_name = Path.basename(parent_dir)
    dir_name_lower = String.downcase(dir_name)

    standalone_patterns =
      @default_standalone_patterns ++
        Enum.map(library.standalone_folders || [], &String.downcase/1)

    at_root = dir_name == Path.basename(library.root_path)
    is_standalone_folder = dir_name_lower in standalone_patterns

    name =
      cond do
        at_root -> nil
        is_standalone_folder -> nil
        true -> dir_name
      end

    if name do
      {clean_name, start_year, end_year, ongoing} = parse_folder_name(name)

      case Map.get(cache, clean_name) do
        nil ->
          case Library.create_or_find_series(%{
                 library_id: library.id,
                 name: clean_name,
                 path: parent_dir,
                 start_year: start_year,
                 end_year: end_year,
                 ongoing: ongoing
               }) do
            {:ok, series} -> {series, Map.put(cache, clean_name, series)}
            _ -> {nil, cache}
          end

        series ->
          if series.path != parent_dir or series.ongoing != ongoing do
            case Library.update_series_folder_meta(series, %{
                   path: parent_dir,
                   start_year: start_year,
                   end_year: end_year,
                   ongoing: ongoing
                 }) do
              {:ok, updated} -> {updated, Map.put(cache, clean_name, updated)}
              _ -> {series, cache}
            end
          else
            {series, cache}
          end
      end
    else
      {nil, cache}
    end
  end

  defp do_scan_series(series_id, force) do
    series = Library.get_series!(series_id)
    library = Library.get_library!(series.library_id)
    library_id = library.id

    Logger.info("Starting series rescan: #{series.name}")

    files = if series.path && File.dir?(series.path), do: collect_files(series.path), else: []
    total = length(files)

    broadcast_progress(library_id, 0, total)

    series_cache = Library.load_series_cache(library_id)

    parsed_files =
      files
      |> Task.async_stream(&parse_file_metadata/1,
           max_concurrency: @metadata_concurrency,
           ordered: true,
           timeout: 60_000)
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        {:exit, reason} ->
          Logger.error("Metadata parse crashed: #{inspect(reason)}")
          []
      end)

    {thumbnail_jobs, _cache} =
      parsed_files
      |> Enum.with_index(1)
      |> Enum.reduce({[], series_cache}, fn {file_meta, idx}, {jobs, cache} ->
        {job, new_cache} = upsert_book(file_meta, library, force, cache)
        broadcast_progress(library_id, idx, total)
        new_jobs = if job, do: [job | jobs], else: jobs
        {new_jobs, new_cache}
      end)

    thumb_total_s = length(thumbnail_jobs)
    if thumb_total_s > 0 do
      broadcast_progress(library_id, 0, thumb_total_s, false, :thumbnails)
    end
    {:ok, thumb_counter_s} = Agent.start_link(fn -> 0 end)

    thumbnail_jobs
    |> Task.async_stream(
      fn {book, path} ->
        result = generate_thumbnail(book, path)
        n = Agent.get_and_update(thumb_counter_s, fn c -> {c + 1, c + 1} end)
        broadcast_progress(library_id, n, thumb_total_s, false, :thumbnails)
        result
      end,
      max_concurrency: @thumbnail_concurrency,
      ordered: false,
      timeout: 120_000
    )
    |> Stream.run()

    Agent.stop(thumb_counter_s)

    if series.path && File.dir?(series.path) do
      Library.mark_orphaned_series_books(series_id, files)
    end

    Library.update_series_counts(library_id)

    broadcast_progress(library_id, total, total, true)
    Logger.info("Series rescan complete: #{series.name} (#{total} files)")
  end

  defp do_scan_file(library_id, file_path) do
    unless File.regular?(file_path) do
      Logger.warning("FileWatcher: #{file_path} no longer exists, skipping")
    else
      library = Library.get_library!(library_id)
      Logger.info("Scanning file #{file_path}")

      update_task_status(library_id, %{scanned: 0, total: 1, done: false, collecting: false})
      broadcast_progress(library_id, 0, 1, false, :file)

      file_meta = parse_file_metadata(file_path)
      series_cache = Library.load_series_cache(library_id)
      {job, _cache} = upsert_book(file_meta, library, true, series_cache)

      if job do
        {book, path} = job
        broadcast_progress(library_id, 0, 1, false, :thumbnails)
        generate_thumbnail(book, path)
      end

      Library.update_series_counts(library_id)

      update_task_status(library_id, %{scanned: 1, total: 1, done: true})
      broadcast_progress(library_id, 1, 1, true, :file)
    end
  end

  defp collect_files(root_path) do
    case File.ls(root_path) do
      {:ok, _} ->
        Path.wildcard(Path.join([root_path, "**", "*"]))
        |> Enum.filter(fn path ->
          String.downcase(Path.extname(path)) in @supported_formats
        end)

      {:error, reason} ->
        Logger.error("Cannot access library path #{root_path}: #{inspect(reason)}")
        []
    end
  end

  defp resolve_page_count(metadata, file_path, fallback) do
    case Map.get(metadata, :page_count) do
      n when is_integer(n) and n > 0 -> n
      _ ->
        case Extractor.get_page_count(file_path) do
          n when n > 0 -> n
          _ -> fallback
        end
    end
  end

  # "Batman (1940-2011)" → {"Batman", 1940, 2011, false}
  # "The Disavowed (2025-)" → {"The Disavowed", 2025, nil, true}
  # "AD Police (1994)" → {"AD Police", 1994, nil, false}
  # "Plain Name" → {"Plain Name", nil, nil, false}
  @doc false
  def parse_folder_name(name) do
    trailing = ~r/(?:\s*\((?!\d{4}[\-)])[^)]+\))+\s*$/
    clean = Regex.replace(trailing, name, "") |> String.trim()

    cond do
      match = Regex.run(~r/^(.+?)\s*\((\d{4})-(\d{4})\)\s*$/, clean) ->
        [_, base, sy, ey] = match
        {String.trim(base), String.to_integer(sy), String.to_integer(ey), false}

      match = Regex.run(~r/^(.+?)\s*\((\d{4})-\)\s*$/, clean) ->
        [_, base, sy] = match
        {String.trim(base), String.to_integer(sy), nil, true}

      match = Regex.run(~r/^(.+?)\s*\((\d{4})\)\s*$/, clean) ->
        [_, base, sy] = match
        {String.trim(base), String.to_integer(sy), nil, false}

      true ->
        {clean, nil, nil, false}
    end
  end

  defp generate_thumbnail(book, file_path) do
    thumb_dir = Application.get_env(:stashix, :thumbnail_dir, "/tmp/stashix/thumbnails")
    File.mkdir_p!(thumb_dir)
    dest = Path.join(thumb_dir, "#{book.id}.jpg")

    result =
      case find_sidecar_image(file_path) do
        nil -> Thumbnail.generate(file_path, dest)
        sidecar -> File.cp(sidecar, dest)
      end

    case result do
      :ok -> Library.create_or_update_cover(book.id, dest)
      {:ok, _} -> Library.create_or_update_cover(book.id, dest)
      {:error, reason} -> Logger.warning("Thumbnail failed for #{file_path}: #{inspect(reason)}")
    end
  end

  @doc false
  def find_sidecar_image(file_path) do
    base = Path.rootname(file_path)

    Enum.find_value(~w(.jpg .jpeg .png .webp), fn ext ->
      path = base <> ext
      if File.exists?(path), do: path
    end)
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

  defp broadcast_progress(library_id, scanned, total, done \\ false, phase \\ :scan) do
    Phoenix.PubSub.broadcast(
      Stashix.PubSub,
      "scan:#{library_id}",
      {:scan_progress, %{library_id: library_id, scanned: scanned, total: total, done: done, phase: phase}}
    )
  end
end
