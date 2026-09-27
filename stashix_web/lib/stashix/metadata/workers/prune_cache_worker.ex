defmodule Stashix.Metadata.Workers.PruneCacheWorker do
  @moduledoc "Deletes expired metadata cache entries (scheduled daily by Oban Cron)."
  use Oban.Worker, queue: :metadata_write, max_attempts: 1

  @impl true
  def perform(_job) do
    Stashix.Metadata.Cache.prune()
    :ok
  end
end
