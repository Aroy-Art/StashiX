defmodule Stashix.Metadata do
  @moduledoc """
  External metadata: identify books/series against source plugins, apply the
  result, queue reviews for uncertain matches and write metadata back to files.

  PubSub:
    * `"metadata"` - `{:metadata_event, map}` for admin pages (reviews, progress)
    * `"metadata:<library_id>"` - `{:metadata_updated, :book | :series, id}`
  """
  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Settings
  alias Stashix.Library.{Book, Series}
  alias Stashix.Metadata.{Apply, Candidate, HTTP, Matcher, MatchReview, Sources}
  alias Stashix.Metadata.Writer.FileWriter
  alias Stashix.Metadata.Workers.{MatchBookWorker, MatchSeriesWorker, MatchLibraryWorker, WriteFileWorker}

  ## Identify (automatic)

  @doc """
  Matches a book and applies a confident result, or records a review.
  Returns `{:applied, book}`, `{:review, review}`, `{:snooze, ms}` or `{:error, reason}`.
  """
  def identify_book(%Book{} = book) do
    settings = Settings.metadata()

    case Matcher.match_book(book, settings) do
      {:matched, source, %Candidate{id: id}} ->
        case apply_issue(book, source.module.key(), id, settings) do
          {:ok, book} -> {:applied, book}
          {:error, {:rate_limited, ms}} -> {:snooze, ms}
          {:error, reason} -> {:error, reason}
        end

      {:review, query, candidates} ->
        {:ok, review} = put_review(%{book_id: book.id, library_id: book.library_id}, query, candidates, nil)
        {:review, review}

      {:error, {:rate_limited, ms}} ->
        {:snooze, ms}

      {:error, :no_sources} = error ->
        error

      {:error, reason} = error ->
        put_review(%{book_id: book.id, library_id: book.library_id}, Matcher.book_query(book), [], describe(reason))
        error
    end
  end

  @doc "Matches the series record itself (not its books)."
  def identify_series(%Series{} = series) do
    settings = Settings.metadata()

    case Matcher.match_series(series, settings) do
      {:matched, source, %Candidate{id: id}} ->
        case apply_series(series, source.module.key(), id, settings) do
          {:ok, series} -> {:applied, series}
          {:error, {:rate_limited, ms}} -> {:snooze, ms}
          {:error, reason} -> {:error, reason}
        end

      {:review, query, candidates} ->
        {:ok, review} = put_review(%{series_id: series.id, library_id: series.library_id}, query, candidates, nil)
        {:review, review}

      {:error, {:rate_limited, ms}} ->
        {:snooze, ms}

      {:error, :no_sources} = error ->
        error

      {:error, reason} = error ->
        put_review(
          %{series_id: series.id, library_id: series.library_id},
          Matcher.series_query(series),
          [],
          describe(reason)
        )

        error
    end
  end

  ## Apply a specific result (manual pick or auto match)

  def apply_issue(%Book{} = book, source_key, issue_id, settings \\ Settings.metadata()) do
    with {:ok, metadata} <- fetch_issue(source_key, issue_id) do
      apply_issue_metadata(book, source_key, metadata, settings)
    end
  end

  @doc "Fetches full issue metadata (used for previews in the Identify dialog). `refresh: true` skips the cache."
  def fetch_issue(source_key, issue_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_key) do
      source.module.fetch_issue(issue_id, HTTP.context(source, opts))
    end
  end

  def fetch_series(source_key, series_id, opts \\ []) do
    with {:ok, source} <- fetch_source(source_key) do
      source.module.fetch_series(series_id, HTTP.context(source, opts))
    end
  end

  @doc "Applies already fetched issue metadata (avoids a second request after a preview)."
  def apply_issue_metadata(%Book{} = book, source_key, metadata, settings \\ Settings.metadata(), opts \\ []) do
    with {:ok, source} <- fetch_source(source_key),
         {:ok, updated} <- Apply.apply_book(book, source.module, metadata, settings, opts) do
      resolve_reviews(book_id: book.id)
      broadcast(book.library_id, {:metadata_updated, :book, book.id})
      maybe_enqueue_write(updated, settings)
      {:ok, updated}
    end
  end

  def apply_series(%Series{} = series, source_key, series_id, settings \\ Settings.metadata()) do
    with {:ok, metadata} <- fetch_series(source_key, series_id) do
      apply_series_metadata(series, source_key, metadata, settings)
    end
  end

  def apply_series_metadata(%Series{} = series, source_key, metadata, settings \\ Settings.metadata(), opts \\ []) do
    with {:ok, source} <- fetch_source(source_key),
         {:ok, updated} <- Apply.apply_series(series, source.module, metadata, settings, opts) do
      resolve_reviews(series_id: series.id)
      broadcast(series.library_id, {:metadata_updated, :series, series.id})
      {:ok, updated}
    end
  end

  defp fetch_source(key) do
    case Sources.get(key) do
      nil -> {:error, :unknown_source}
      source -> {:ok, source}
    end
  end

  @doc "Manual search for the Identify dialog."
  defdelegate search(source_key, kind, query, opts \\ []), to: Matcher

  defdelegate cache_count, to: Stashix.Metadata.Cache, as: :count
  defdelegate clear_cache(source_key \\ nil), to: Stashix.Metadata.Cache, as: :clear

  ## Jobs

  def enqueue_book(book_id, opts \\ []) do
    %{book_id: book_id} |> MatchBookWorker.new(opts) |> Oban.insert()
  end

  @doc "Match a series record and then each of its books. `skip_matched: true` skips already matched books."
  def enqueue_series(series_id, opts \\ []) do
    %{series_id: series_id, skip_matched: Keyword.get(opts, :skip_matched, false)}
    |> MatchSeriesWorker.new()
    |> Oban.insert()
  end

  def enqueue_library(library_id, opts \\ []) do
    %{library_id: library_id, skip_matched: Keyword.get(opts, :skip_matched, true)}
    |> MatchLibraryWorker.new()
    |> Oban.insert()
  end

  def enqueue_write(book_id), do: %{book_id: book_id} |> WriteFileWorker.new() |> Oban.insert()

  defp maybe_enqueue_write(%Book{id: id}, settings) do
    if settings["write_to_files"], do: enqueue_write(id)
  end

  @doc "Writes DB metadata into the book's files now (used by WriteFileWorker)."
  def write_book_files(%Book{} = book), do: FileWriter.write_book(book, Settings.metadata())

  @doc "Counts of metadata jobs by state, for the admin page."
  def job_counts do
    from(j in Oban.Job,
      where: j.queue in ["metadata", "metadata_write"],
      group_by: [j.queue, j.state],
      select: {j.queue, j.state, count(j.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {q, s, c}, acc -> Map.update(acc, q, %{s => c}, &Map.put(&1, s, c)) end)
  end

  def retry_failed_jobs do
    from(j in Oban.Job, where: j.queue in ["metadata", "metadata_write"] and j.state in ["discarded", "retryable"])
    |> Oban.retry_all_jobs()
  end

  def cancel_pending_jobs do
    from(j in Oban.Job,
      where: j.queue in ["metadata", "metadata_write"] and j.state in ["available", "scheduled", "retryable"]
    )
    |> Oban.cancel_all_jobs()
  end

  ## Reviews

  def list_reviews(opts \\ []) do
    status = Keyword.get(opts, :status, "pending")

    from(r in MatchReview,
      where: r.status == ^status,
      order_by: [desc: r.updated_at],
      limit: ^Keyword.get(opts, :limit, 100),
      preload: [book: [:series, :cover], series: []]
    )
    |> Repo.all()
  end

  def count_reviews(status \\ "pending") do
    Repo.aggregate(from(r in MatchReview, where: r.status == ^status), :count)
  end

  def get_review!(id), do: Repo.get!(MatchReview, id) |> Repo.preload(book: [:series, :cover], series: [])

  def pending_review_for(book_id: book_id),
    do: Repo.one(from r in MatchReview, where: r.book_id == ^book_id and r.status == "pending", limit: 1)

  def pending_review_for(series_id: series_id),
    do:
      Repo.one(
        from r in MatchReview,
          where: r.series_id == ^series_id and is_nil(r.book_id) and r.status == "pending",
          limit: 1
      )

  def skip_review(%MatchReview{} = review) do
    result = review |> MatchReview.changeset(%{status: "skipped"}) |> Repo.update()
    broadcast_admin(%{type: :review_changed})
    result
  end

  def review_candidates(%MatchReview{candidates: list}), do: Enum.map(list, &Candidate.from_map/1)

  defp put_review(owner, query, candidates, error) do
    key = if owner[:book_id], do: [book_id: owner.book_id], else: [series_id: owner.series_id]

    attrs =
      Map.merge(owner, %{
        status: "pending",
        query: query,
        candidates: Enum.map(candidates, &Candidate.to_map/1),
        error: error
      })

    result =
      case pending_review_for(key) do
        nil -> %MatchReview{} |> MatchReview.changeset(attrs) |> Repo.insert()
        existing -> existing |> MatchReview.changeset(attrs) |> Repo.update()
      end

    broadcast_admin(%{type: :review_changed})
    result
  end

  defp resolve_reviews(book_id: id) do
    from(r in MatchReview, where: r.book_id == ^id and r.status == "pending")
    |> Repo.update_all(set: [status: "resolved", updated_at: NaiveDateTime.utc_now(:second)])

    broadcast_admin(%{type: :review_changed})
  end

  defp resolve_reviews(series_id: id) do
    from(r in MatchReview, where: r.series_id == ^id and is_nil(r.book_id) and r.status == "pending")
    |> Repo.update_all(set: [status: "resolved", updated_at: NaiveDateTime.utc_now(:second)])

    broadcast_admin(%{type: :review_changed})
  end

  ## Misc

  def set_locked(%Book{} = book, locked),
    do: book |> Book.changeset(%{metadata_locked: locked}) |> Repo.update()

  def set_locked(%Series{} = series, locked),
    do: series |> Series.changeset(%{metadata_locked: locked}) |> Repo.update()

  @doc "Tests a source's connection and records the result."
  def test_source(source_key) do
    with {:ok, %{module: mod, config: row} = source} <- fetch_source(source_key) do
      result =
        if Sources.configured?(mod, row.config),
          do: mod.test_connection(HTTP.context(source)),
          else: {:error, HTTP.error_message(:not_configured)}

      {status, message} =
        case result do
          :ok -> {"ok", "Connected"}
          {:error, msg} -> {"error", describe(msg)}
        end

      Sources.update(row, %{
        last_tested_at: NaiveDateTime.utc_now(:second),
        last_test_status: status,
        last_test_message: message
      })

      result
    end
  end

  def describe({:sources_failed, errors}),
    do: Enum.map_join(errors, "; ", fn {k, r} -> "#{k}: #{HTTP.error_message(r)}" end)

  def describe(:no_sources), do: "No metadata sources are enabled and configured"
  def describe(:unknown_source), do: "Unknown metadata source"
  def describe(reason), do: HTTP.error_message(reason)

  def broadcast(library_id, msg), do: Phoenix.PubSub.broadcast(Stashix.PubSub, "metadata:#{library_id}", msg)
  def broadcast_admin(event), do: Phoenix.PubSub.broadcast(Stashix.PubSub, "metadata", {:metadata_event, event})

  def subscribe(library_id), do: Phoenix.PubSub.subscribe(Stashix.PubSub, "metadata:#{library_id}")
  def subscribe_admin, do: Phoenix.PubSub.subscribe(Stashix.PubSub, "metadata")
end
