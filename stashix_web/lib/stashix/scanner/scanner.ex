defmodule Stashix.Scanner do
  use GenServer
  require Logger

  alias Stashix.Library
  alias Stashix.Media.{Thumbnail, Extractor}
  alias Stashix.Metadata.Parser

  @supported_formats ~w(.cbz .cbr .cb7 .epub .pdf)
  @ets_table :scan_tasks
  @metadata_concurrency 16
  @collect_concurrency 16
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

  def scan_book(book_id) do
    GenServer.cast(__MODULE__, {:scan_book, book_id})
  end

  def backfill_blurhashes do
    GenServer.cast(__MODULE__, :backfill_blurhashes)
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

  def handle_cast({:scan_book, book_id}, state) do
    Task.Supervisor.start_child(Stashix.Scanner.TaskSupervisor, fn ->
      book = Library.get_book!(book_id)
      files = Library.get_book_files(book_id)
      Enum.each(files, fn bf -> do_scan_file(book.library_id, bf.path) end)
    end)

    {:noreply, state}
  end

  def handle_cast(:backfill_blurhashes, state) do
    Task.Supervisor.start_child(Stashix.Scanner.TaskSupervisor, fn ->
      covers = Library.list_covers_without_blurhash()
      total = length(covers)
      Logger.info("Blurhash backfill: #{total} covers to process")

      covers
      |> Task.async_stream(
        fn {book_id, path} -> save_cover_with_blurhash(book_id, path) end,
        max_concurrency: @thumbnail_concurrency,
        ordered: false,
        timeout: 60_000
      )
      |> Stream.with_index(1)
      |> Stream.each(fn {_, n} ->
        if rem(n, 50) == 0, do: Logger.info("Blurhash backfill: #{n}/#{total}")
      end)
      |> Stream.run()

      Logger.info("Blurhash backfill complete")
    end)

    {:noreply, state}
  end

  defp do_scan(library_id, force) do
    library = Library.get_library!(library_id)
    Logger.info("Starting scan for library #{library.name} at #{library.root_path}")

    update_task_status(library_id, %{scanned: 0, total: 0, done: false, phase: :collecting})
    broadcast_progress(library_id, 0, 0, false, :collecting)

    files = collect_files(library.root_path)
    total = length(files)

    series_cache = Library.load_series_cache(library_id) |> normalize_series_names()
    books_cache = if force, do: %{}, else: Library.load_books_cache(library_id)

    {files_to_parse, files_unchanged} =
      Enum.split_with(files, fn path ->
        case Map.get(books_cache, path) do
          nil ->
            true

          %{deleted_at: da} when not is_nil(da) ->
            true

          %{last_modified: lm} ->
            file_changed?(path, lm)
        end
      end)

    unchanged_count = length(files_unchanged)
    parse_count = length(files_to_parse)

    Logger.info("[scan] books_cache=#{map_size(books_cache)} #{unchanged_count} unchanged, #{parse_count} need parse")

    update_task_status(library_id, %{
      scanned: unchanged_count,
      total: total,
      done: false,
      phase: :parsing
    })

    broadcast_progress(library_id, unchanged_count, total, false, :parsing)

    parsed_files =
      files_to_parse
      |> Task.async_stream(&parse_file_metadata/1,
        max_concurrency: @metadata_concurrency,
        ordered: true,
        timeout: 60_000
      )
      |> Enum.flat_map(fn
        {:ok, result} ->
          [result]

        {:exit, reason} ->
          Logger.error("Metadata parse crashed: #{inspect(reason)}")
          []
      end)

    series_cache = detect_renamed_series(parsed_files, series_cache, library)

    update_task_status(library_id, %{
      scanned: unchanged_count,
      total: total,
      done: false,
      phase: :importing
    })

    broadcast_progress(library_id, unchanged_count, total, false, :importing)

    {thumbnail_jobs, _cache} =
      parsed_files
      |> Enum.with_index(unchanged_count + 1)
      |> Enum.reduce({[], series_cache}, fn {file_meta, idx}, {jobs, cache} ->
        {job, new_cache} = upsert_book(file_meta, library, force, cache)

        update_task_status(library_id, %{
          scanned: idx,
          total: total,
          done: false,
          phase: :importing
        })

        broadcast_progress(library_id, idx, total, false, :importing)
        new_jobs = if job, do: [job | jobs], else: jobs
        {new_jobs, new_cache}
      end)

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
    case Library.get_book_file_by_path(file_path) do
      nil ->
        case Library.get_book_file_by_hash(file_hash) do
          nil -> create_book_from_meta(file_meta, library, cache)
          existing_file -> move_book_file(existing_file, file_meta, library, cache)
        end

      existing_file ->
        was_deleted = existing_file.deleted_at != nil

        modified =
          NaiveDateTime.compare(
            last_modified,
            existing_file.last_modified || ~N[1970-01-01 00:00:00]
          ) == :gt

        if force || was_deleted || modified do
          update_book_file_from_meta(existing_file, file_meta, library, cache)
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

    format =
      file_path
      |> Path.extname()
      |> String.downcase()
      |> String.trim_leading(".")
      |> String.to_atom()

    stem = Path.basename(file_path, Path.extname(file_path))
    dir = Path.dirname(file_path)
    existing_book = Library.get_book_by_stem(dir, stem)

    book =
      if existing_book do
        existing_book
      else
        book_attrs = %{
          library_id: library.id,
          series_id: series && series.id,
          title: Map.get(metadata, :title) || filename,
          type: if(series, do: "issue", else: "standalone"),
          issue_number: if(series, do: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)),
          volume: Map.get(metadata, :volume),
          year: Map.get(metadata, :year),
          page_count: resolve_page_count(metadata, file_path, 0),
          language: Map.get(metadata, :language, "en"),
          summary: Map.get(metadata, :summary),
          age_rating: Map.get(metadata, :age_rating),
          community_rating: Map.get(metadata, :community_rating)
        }

        case Library.create_book(book_attrs) do
          {:ok, b} ->
            link_publisher(b, series, enrich_publisher(metadata, file_path, library))
            Phoenix.PubSub.broadcast(Stashix.PubSub, "scan:#{library.id}", {:book_added, b})
            b

          {:error, reason} ->
            Logger.error("Failed to create book for #{file_path}: #{inspect(reason)}")
            nil
        end
      end

    if book do
      file_attrs = %{
        book_id: book.id,
        path: file_path,
        format: format,
        file_size: file_size,
        file_hash: file_hash,
        last_modified: last_modified,
        page_count: resolve_page_count(metadata, file_path, 0),
        source_format: Map.get(parsed, :source_format)
      }

      case Library.create_book_file(file_attrs) do
        {:ok, _book_file} ->
          if existing_book do
            pc = resolve_page_count(metadata, file_path, 0)
            if pc > 0, do: Library.update_book(book, %{page_count: pc})
          end

          {{book, file_path}, new_cache}

        {:error, reason} ->
          Logger.error("Failed to create book_file for #{file_path}: #{inspect(reason)}")
          {nil, new_cache}
      end
    else
      {nil, new_cache}
    end
  end

  defp move_book_file(
         book_file,
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
    file_attrs = %{
      path: file_path,
      file_hash: file_hash,
      last_modified: last_modified,
      file_size: file_size,
      page_count: resolve_page_count(metadata, file_path, book_file.page_count),
      source_format: Map.get(parsed, :source_format),
      deleted_at: nil
    }

    case Library.update_book_file(book_file, file_attrs) do
      {:ok, _} ->
        book = Library.get_book!(book_file.book_id)
        filename = Path.basename(file_path, Path.extname(file_path))
        {series, new_cache} = find_or_create_series_cached(file_path, library, cache)

        book_attrs = %{
          title: Map.get(metadata, :title) || filename,
          issue_number: if(series, do: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)),
          volume: Map.get(metadata, :volume),
          year: Map.get(metadata, :year),
          series_id: series && series.id,
          type: if(series, do: "issue", else: "standalone"),
          deleted_at: nil
        }

        Library.update_book(book, book_attrs)
        {{book, file_path}, new_cache}

      {:error, reason} ->
        Logger.error("Failed to move book_file #{file_path}: #{inspect(reason)}")
        {nil, cache}
    end
  end

  defp update_book_file_from_meta(
         book_file,
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
    book = Library.get_book!(book_file.book_id)
    {series, new_cache} = find_or_create_series_cached(file_path, library, cache)
    filename = Path.basename(file_path, Path.extname(file_path))

    book_attrs = %{
      title: Map.get(metadata, :title) || filename,
      issue_number: if(series, do: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number)),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      series_id: series && series.id,
      type: if(series, do: "issue", else: "standalone"),
      page_count: resolve_page_count(metadata, file_path, book.page_count),
      language: Map.get(metadata, :language, book.language),
      summary: Map.get(metadata, :summary, book.summary),
      deleted_at: nil
    }

    file_attrs = %{
      path: file_path,
      file_hash: file_hash,
      last_modified: last_modified,
      file_size: file_size,
      page_count: resolve_page_count(metadata, file_path, book_file.page_count),
      source_format: Map.get(parsed, :source_format),
      deleted_at: nil
    }

    with {:ok, _updated_book} <- Library.update_book(book, book_attrs),
         {:ok, _updated_file} <- Library.update_book_file(book_file, file_attrs) do
      {{book, file_path}, new_cache}
    else
      {:error, reason} ->
        Logger.error("Failed to update book/file for #{file_path}: #{inspect(reason)}")
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

      case Map.get(cache, parent_dir) do
        nil ->
          case Library.create_or_find_series(%{
                 library_id: library.id,
                 name: clean_name,
                 path: parent_dir,
                 start_year: start_year,
                 end_year: end_year,
                 ongoing: ongoing
               }) do
            {:ok, series} -> {series, Map.put(cache, parent_dir, series)}
            _ -> {nil, cache}
          end

        series ->
          if series.ongoing != ongoing or series.name != clean_name do
            case Library.update_series_folder_meta(series, %{
                   name: clean_name,
                   path: parent_dir,
                   start_year: start_year,
                   end_year: end_year,
                   ongoing: ongoing
                 }) do
              {:ok, updated} -> {updated, Map.put(cache, parent_dir, updated)}
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
        timeout: 60_000
      )
      |> Enum.flat_map(fn
        {:ok, result} ->
          [result]

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

  defp normalize_series_names(series_cache) do
    Enum.reduce(series_cache, series_cache, fn {path, series}, cache ->
      {clean_name, _, _, _} = parse_folder_name(series.name)

      if clean_name != series.name do
        case Library.update_series_folder_meta(series, %{name: clean_name}) do
          {:ok, updated} -> Map.put(cache, path, updated)
          _ -> cache
        end
      else
        cache
      end
    end)
  end

  defp detect_renamed_series(parsed_files, series_cache, library) do
    new_dir_files =
      parsed_files
      |> Enum.group_by(fn %{file_path: p} -> Path.dirname(p) end)
      |> Enum.reject(fn {dir, _} -> Map.has_key?(series_cache, dir) end)

    if new_dir_files == [] do
      series_cache
    else
      all_hashes =
        Enum.flat_map(new_dir_files, fn {_, files} -> Enum.map(files, & &1.file_hash) end)

      hash_to_series = Library.load_hash_series_map(library.id, all_hashes)

      Enum.reduce(new_dir_files, series_cache, fn {dir, files}, cache ->
        old_series =
          files
          |> Enum.map(&Map.get(hash_to_series, &1.file_hash))
          |> Enum.reject(&is_nil/1)
          |> Enum.frequencies_by(& &1.id)
          |> Enum.max_by(fn {_, count} -> count end, fn -> nil end)
          |> case do
            nil ->
              nil

            {_id, _} ->
              files
              |> Enum.find_value(&Map.get(hash_to_series, &1.file_hash))
          end

        case old_series && Library.update_series_folder_meta(old_series, %{path: dir}) do
          {:ok, updated} ->
            Logger.info("[scan] Series rename detected: #{old_series.path} → #{dir}")
            cache |> Map.delete(old_series.path) |> Map.put(dir, updated)

          _ ->
            cache
        end
      end)
    end
  end

  defp collect_files(root_path) do
    case File.ls(root_path) do
      {:ok, _} ->
        collect_recursive([root_path], [])

      {:error, reason} ->
        Logger.error("Cannot access library path #{root_path}: #{inspect(reason)}")
        []
    end
  end

  defp collect_recursive([], files), do: files

  defp collect_recursive(dirs, files) do
    {next_dirs, new_files} =
      dirs
      |> Task.async_stream(
        fn dir ->
          case File.ls(dir) do
            {:ok, entries} ->
              entries
              |> Enum.map(&Path.join(dir, &1))
              |> Enum.split_with(&File.dir?/1)

            _ ->
              {[], []}
          end
        end,
        max_concurrency: @collect_concurrency,
        ordered: false,
        timeout: 30_000
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {subdirs, entries}}, {all_dirs, all_files} ->
          supported =
            Enum.filter(entries, fn p ->
              String.downcase(Path.extname(p)) in @supported_formats
            end)

          {all_dirs ++ subdirs, all_files ++ supported}

        _, acc ->
          acc
      end)

    collect_recursive(next_dirs, files ++ new_files)
  end

  defp resolve_page_count(metadata, file_path, fallback) do
    case Map.get(metadata, :page_count) do
      n when is_integer(n) and n > 0 ->
        n

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
      :ok -> save_cover_with_blurhash(book.id, dest)
      {:ok, _} -> save_cover_with_blurhash(book.id, dest)
      {:error, reason} -> Logger.warning("Thumbnail failed for #{file_path}: #{inspect(reason)}")
    end
  end

  defp save_cover_with_blurhash(book_id, path) do
    blurhash =
      with {:ok, img} <- Image.open(path),
           {:ok, small} <- Image.thumbnail(img, 64),
           {:ok, flat} <- Image.flatten(small),
           {:ok, hash} <- Image.Blurhash.encode(flat, x_components: 4, y_components: 3) do
        hash
      else
        _ -> nil
      end

    Library.create_or_update_cover(book_id, path, blurhash)
  end

  @doc false
  def find_sidecar_image(file_path) do
    base = Path.rootname(file_path)

    Enum.find_value(~w(.jpg .jpeg .png .webp), fn ext ->
      path = base <> ext
      if File.exists?(path), do: path
    end)
  end

  defp enrich_publisher(metadata, file_path, library) do
    if Map.has_key?(metadata, :publisher) do
      metadata
    else
      series_dir = Path.dirname(file_path)
      publisher_dir = Path.dirname(series_dir)

      if Path.dirname(publisher_dir) == library.root_path do
        Map.put(metadata, :publisher, Path.basename(publisher_dir))
      else
        metadata
      end
    end
  end

  defp link_publisher(book, series, metadata) do
    case Map.get(metadata, :publisher) do
      nil ->
        :ok

      name ->
        case Library.get_or_create_publisher(name) do
          {:ok, publisher} ->
            Library.link_publisher_to_book(book.id, publisher.id)
            if series, do: Library.link_publisher_to_series(series.id, publisher.id)

          _ ->
            :ok
        end
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

  defp file_changed?(path, lm) do
    case File.stat(path) do
      {:ok, stat} -> NaiveDateTime.compare(NaiveDateTime.from_erl!(stat.mtime), lm) != :eq
      _ -> true
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
