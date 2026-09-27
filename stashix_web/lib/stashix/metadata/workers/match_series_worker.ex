defmodule Stashix.Metadata.Workers.MatchSeriesWorker do
  @moduledoc """
  Identifies a series record, then fans out a MatchBookWorker per book. Books run
  after the series so they can reuse the series' external id (fewer requests).
  """
  use Oban.Worker,
    queue: :metadata,
    max_attempts: 5,
    unique: [keys: [:series_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Stashix.Repo
  alias Stashix.Library.Series
  alias Stashix.Metadata
  alias Stashix.Metadata.Matcher
  alias Stashix.Metadata.Workers.MatchBookWorker

  @impl true
  def perform(%Oban.Job{args: %{"series_id" => id} = args}) do
    case Repo.get(Series, id) do
      nil ->
        {:cancel, :not_found}

      series ->
        result = if series.metadata_locked, do: :locked, else: Metadata.identify_series(series)

        case result do
          {:snooze, ms} ->
            {:snooze, max(div(ms, 1000), 5)}

          {:error, :no_sources} ->
            {:cancel, :no_sources}

          _ ->
            book_ids = Matcher.series_book_ids(id, skip_matched: args["skip_matched"] == true)
            book_ids |> Enum.map(&MatchBookWorker.new(%{book_id: &1})) |> Oban.insert_all()
            Metadata.broadcast_admin(%{type: :queued, count: length(book_ids)})
            :ok
        end
    end
  end
end
