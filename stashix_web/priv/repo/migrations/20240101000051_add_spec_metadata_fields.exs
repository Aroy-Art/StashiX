# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddSpecMetadataFields do
  use Ecto.Migration

  # Fields of MetronInfo / ComicInfo that had no column, and per-field locks.
  def change do
    alter table(:books) do
      add :manga_volume, :string
      add :alternate_series, :string
      add :alternate_count, :integer
      add :series_group, :string
      add :main_character_or_team, :string
      add :scan_information, :text
      add :review, :text
      add :black_and_white, :boolean
      add :manga, :string
      add :locked_fields, {:array, :string}, null: false, default: []
    end

    alter table(:series) do
      add :status, :string
      add :locked_fields, {:array, :string}, null: false, default: []
    end
  end
end
