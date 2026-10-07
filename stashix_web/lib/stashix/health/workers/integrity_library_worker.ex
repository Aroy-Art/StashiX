defmodule Stashix.Health.Workers.IntegrityLibraryWorker do
  @moduledoc "Fans out IntegrityFileWorker jobs for every active file in a library."
  use Oban.Worker,
    queue: :health,
    max_attempts: 2,
    unique: [keys: [:library_id], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, BookFile}
  alias Stashix.Health
  alias Stashix.Health.Workers.IntegrityFileWorker

  @impl true
  def perform(%Oban.Job{args: %{"library_id" => library_id}}) do
    Health.clear_integrity_results(library_id)

    file_ids =
      from(bf in BookFile,
        join: b in Book,
        on: b.id == bf.book_id,
        where: b.library_id == ^library_id and is_nil(bf.deleted_at),
        select: {bf.id, b.library_id}
      )
      |> Repo.all()

    jobs =
      Enum.map(file_ids, fn {bf_id, lib_id} ->
        IntegrityFileWorker.new(%{book_file_id: bf_id, library_id: lib_id})
      end)

    jobs |> Enum.chunk_every(500) |> Enum.each(&Oban.insert_all/1)

    Health.broadcast(library_id, {:integrity_started, %{library_id: library_id, total: length(jobs)}})
    :ok
  end
end
