defmodule Stashix.Scanner do
  use GenServer
  require Logger

  alias Stashix.Library
  alias Stashix.Media.{Thumbnail, Extractor}
  alias Stashix.Metadata.Parser

  @supported_formats ~w(.cbz .cbr .cb7 .epub .pdf)
  @ets_table :scan_tasks

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def scan_library(library_id, force \\ false) do
    GenServer.cast(__MODULE__, {:scan, library_id, force})
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

    if File.dir?(library.root_path) do
      Library.mark_orphaned_books(library_id, files)
      Library.mark_empty_series_deleted(library_id)
    end

    Library.update_series_counts(library_id)

    update_task_status(library_id, %{scanned: total, total: total, done: true})
    broadcast_progress(library_id, total, total, true)

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
            reimport_book(existing_book, file_path, library, file_hash, last_modified, stat.size)
        end

      existing_book ->
        was_deleted = existing_book.deleted_at != nil
        modified = NaiveDateTime.compare(last_modified, existing_book.last_modified || ~N[1970-01-01 00:00:00]) == :gt

        if force || was_deleted || modified do
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
      type: if(series, do: "issue", else: "standalone"),
      issue_number: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      page_count: resolve_page_count(metadata, file_path, 0),
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

  defp reimport_book(book, file_path, library, file_hash, last_modified, file_size) do
    filename = Path.basename(file_path, Path.extname(file_path))
    parsed = Parser.parse_filename(filename)
    comicinfo = Parser.parse_comicinfo(file_path)
    metadata = Map.merge(parsed, comicinfo)

    series = find_or_create_series(file_path, library, metadata)

    attrs = %{
      path: file_path,
      title: Map.get(metadata, :title) || filename,
      issue_number: Map.get(parsed, :issue_number) || Map.get(comicinfo, :issue_number),
      volume: Map.get(metadata, :volume),
      year: Map.get(metadata, :year),
      series_id: series && series.id,
      type: if(series, do: "issue", else: "standalone"),
      page_count: resolve_page_count(metadata, file_path, book.page_count),
      language: Map.get(metadata, :language, book.language),
      summary: Map.get(metadata, :summary, book.summary),
      file_hash: file_hash,
      file_size: file_size,
      last_modified: last_modified,
      deleted_at: nil
    }

    case Library.update_book(book, attrs) do
      {:ok, updated_book} -> generate_thumbnail(updated_book, file_path)
      {:error, reason} -> Logger.error("Failed to reimport #{file_path}: #{inspect(reason)}")
    end
  end

  @default_standalone_patterns ["one-shot", "one shot", "oneshot"]

  defp find_or_create_series(file_path, library, _metadata) do
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

      case Library.create_or_find_series(%{
             library_id: library.id,
             name: clean_name,
             path: parent_dir,
             start_year: start_year,
             end_year: end_year,
             ongoing: ongoing
           }) do
        {:ok, series} -> series
        _ -> nil
      end
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
    cond do
      # "Series Name (YYYY-YYYY)" — start and end year
      match = Regex.run(~r/^(.+?)\s*\((\d{4})-(\d{4})\)\s*$/, name) ->
        [_, base, sy, ey] = match
        {String.trim(base), String.to_integer(sy), String.to_integer(ey), false}

      # "Series Name (YYYY-)" — ongoing
      match = Regex.run(~r/^(.+?)\s*\((\d{4})-\)\s*$/, name) ->
        [_, base, sy] = match
        {String.trim(base), String.to_integer(sy), nil, true}

      # "Series Name (YYYY)" — single year
      match = Regex.run(~r/^(.+?)\s*\((\d{4})\)\s*$/, name) ->
        [_, base, sy] = match
        {String.trim(base), String.to_integer(sy), nil, false}

      true ->
        {name, nil, nil, false}
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

  defp broadcast_progress(library_id, scanned, total, done \\ false) do
    Phoenix.PubSub.broadcast(
      Stashix.PubSub,
      "scan:#{library_id}",
      {:scan_progress, %{library_id: library_id, scanned: scanned, total: total, done: done}}
    )
  end
end
