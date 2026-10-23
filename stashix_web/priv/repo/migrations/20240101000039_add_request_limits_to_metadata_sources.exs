# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddRequestLimitsToMetadataSources do
  use Ecto.Migration

  def change do
    alter table(:metadata_sources) do
      add :request_interval_ms, :integer
      add :endpoint_limit_per_hour, :integer
    end
  end
end
