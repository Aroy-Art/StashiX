# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Workers.PruneRenderCacheWorker do
  @moduledoc "Deletes rendered pages not used for a while (scheduled daily by Oban Cron)."
  use Oban.Worker, queue: :health, max_attempts: 1

  @impl true
  def perform(_job) do
    Stashix.Media.RenderCache.prune()
    :ok
  end
end
