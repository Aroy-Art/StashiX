defmodule Stashix.Health.Workers.IntegrityFileWorker do
  @moduledoc "Checks one book_file archive for readability and persists the result."
  use Oban.Worker,
    queue: :health,
    max_attempts: 2,
    unique: [keys: [:book_file_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Stashix.Repo
  alias Stashix.Library.{Book, BookFile}
  alias Stashix.Media.Extractor
  alias Stashix.Health

  @impl true
  def perform(%Oban.Job{args: %{"book_file_id" => bf_id, "library_id" => library_id}}) do
    case Repo.get(BookFile, bf_id) do
      nil ->
        {:cancel, :not_found}

      %BookFile{deleted_at: d} when not is_nil(d) ->
        {:cancel, :deleted}

      %BookFile{path: path} = bf ->
        {status, error} = check_file(path)
        Health.upsert_integrity_result(library_id, bf.id, path, status, error)

        book = Repo.get(Book, bf.book_id)

        Health.broadcast(
          library_id,
          {:integrity_file_done, %{library_id: library_id, book_file_id: bf_id, status: status, book: book}}
        )

        :ok
    end
  end

  defp format_error(:bad_crc), do: "CRC mismatch — archive is corrupted"
  defp format_error(:file_read_error), do: "Could not read file"
  defp format_error(:bad_magic), do: "Not a valid archive (wrong file signature)"
  defp format_error({:bad_crc, _}), do: "CRC mismatch — archive is corrupted"
  defp format_error({:zip_error, msg}) when is_binary(msg), do: "ZIP error: #{msg}"

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_error(reason), do: inspect(reason)

  defp check_file(path) do
    cond do
      not File.exists?(path) ->
        {:error, "File not found on disk"}

      true ->
        case Extractor.list_pages(path) do
          {:ok, pages} when pages == [] ->
            {:error, "Archive contains no readable pages"}

          {:ok, _pages} ->
            {:ok, nil}

          {:error, reason} ->
            {:error, format_error(reason)}
        end
    end
  end
end
