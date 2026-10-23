# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Workers.PruneCacheWorker do
  @moduledoc "Deletes expired metadata cache entries and cached images (scheduled daily by Oban Cron)."
  use Oban.Worker, queue: :metadata_write, max_attempts: 1

  @impl true
  def perform(_job) do
    Stashix.Metadata.Cache.prune()
    Stashix.Metadata.ImageProxy.prune()
    :ok
  end
end
