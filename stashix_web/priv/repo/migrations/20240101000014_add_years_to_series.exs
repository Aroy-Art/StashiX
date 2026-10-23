# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddYearsToSeries do
  use Ecto.Migration

  def change do
    alter table(:series) do
      add :start_year, :integer
      add :end_year, :integer
    end
  end
end
