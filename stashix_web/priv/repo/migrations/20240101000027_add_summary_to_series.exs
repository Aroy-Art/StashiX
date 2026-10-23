# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddSummaryToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :summary, :text
    end
  end
end
