defmodule Stashix.Metadata.Workers.MatchBookWorker do
  @moduledoc "Identifies one book against the enabled metadata sources."
  use Oban.Worker,
    queue: :metadata,
    max_attempts: 5,
    unique: [keys: [:book_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Stashix.Repo
  alias Stashix.Library.Book

  @impl true
  def perform(%Oban.Job{args: %{"book_id" => id}}) do
    case Repo.get(Book, id) do
      nil ->
        {:cancel, :not_found}

      %Book{deleted_at: d} when not is_nil(d) ->
        {:cancel, :deleted}

      book ->
        case Stashix.Metadata.identify_book(book) do
          {:applied, _} -> :ok
          {:review, _} -> :ok
          {:snooze, ms} -> {:snooze, max(div(ms, 1000), 5)}
          {:error, :no_sources} -> {:cancel, :no_sources}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
