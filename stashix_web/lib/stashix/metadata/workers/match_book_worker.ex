defmodule Stashix.Metadata.Workers.MatchBookWorker do
  @moduledoc "Identifies one book against the enabled metadata sources."
  use Oban.Worker,
    queue: :metadata,
    max_attempts: 5,
    unique: [keys: [:book_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Stashix.Repo
  alias Stashix.Library.Book

  @impl true
  def perform(%Oban.Job{args: %{"book_id" => id} = args}) do
    case Repo.get(Book, id) do
      nil ->
        {:cancel, :not_found}

      %Book{deleted_at: d} when not is_nil(d) ->
        {:cancel, :deleted}

      book ->
        opts = if args["overwrite_title"], do: [overwrite_title: true], else: []

        result =
          case {args["source_key"], args["series_source_id"]} do
            {key, sid} when is_binary(key) and is_binary(sid) ->
              case Stashix.Metadata.apply_issue_in_series(book, key, sid, opts) do
                {:ok, _} -> {:applied, book}
                {:error, :not_found} -> Stashix.Metadata.identify_book(book, opts)
                {:error, {:rate_limited, ms}} -> {:snooze, ms}
                {:error, _} = err -> err
              end

            _ ->
              Stashix.Metadata.identify_book(book, opts)
          end

        case result do
          {:applied, _} -> :ok
          {:review, _} -> :ok
          {:snooze, ms} -> {:snooze, max(div(ms, 1000), 5)}
          {:error, :no_sources} -> {:cancel, :no_sources}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
