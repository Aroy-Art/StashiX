defmodule Stashix.Metadata.Workers.WriteFileWorker do
  @moduledoc "Writes a book's metadata into its files (CBZ embed or sidecar XML)."
  use Oban.Worker,
    queue: :metadata_write,
    max_attempts: 3,
    unique: [keys: [:book_id], states: [:available, :scheduled, :retryable]]

  alias Stashix.Repo
  alias Stashix.Library.Book

  @impl true
  def perform(%Oban.Job{args: %{"book_id" => id}}) do
    case Repo.get(Book, id) do
      nil -> {:cancel, :not_found}
      book -> Stashix.Metadata.write_book_files(book)
    end
  end
end
