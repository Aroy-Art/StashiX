defmodule Stashix.Metadata.Workers.MatchLibraryWorker do
  @moduledoc "Queues a MatchSeriesWorker for every series and a MatchBookWorker for every standalone book."
  use Oban.Worker,
    queue: :metadata,
    max_attempts: 3,
    unique: [keys: [:library_id], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, Series}
  alias Stashix.Metadata
  alias Stashix.Metadata.Workers.{MatchBookWorker, MatchSeriesWorker}

  @impl true
  def perform(%Oban.Job{args: %{"library_id" => library_id} = args}) do
    skip_matched = args["skip_matched"] != false

    series_ids =
      from(s in Series,
        where: s.library_id == ^library_id and is_nil(s.deleted_at) and not s.metadata_locked,
        select: s.id
      )
      |> Repo.all()

    standalone_q =
      from(b in Book,
        where:
          b.library_id == ^library_id and is_nil(b.series_id) and is_nil(b.deleted_at) and
            not b.metadata_locked,
        select: b.id
      )

    standalone_q = if skip_matched, do: where(standalone_q, [b], is_nil(b.metadata_matched_at)), else: standalone_q
    book_ids = Repo.all(standalone_q)

    jobs =
      Enum.map(series_ids, &MatchSeriesWorker.new(%{series_id: &1, skip_matched: skip_matched})) ++
        Enum.map(book_ids, &MatchBookWorker.new(%{book_id: &1}))

    jobs |> Enum.chunk_every(500) |> Enum.each(&Oban.insert_all/1)
    Metadata.broadcast_admin(%{type: :queued, count: length(jobs)})
    :ok
  end
end
