# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCalibreSync do
  use Ecto.Migration

  # Calibre libraries (docs/calibre-plan.md): a library filled from a Calibre
  # `metadata.db` instead of a folder scan, and the ids that tie Stashix rows
  # to Calibre's.
  def change do
    alter table(:libraries) do
      add :source, :string, null: false, default: "folders"
      # Snapshot stamp, last sync time, counts and errors.
      add :calibre_state, :map, null: false, default: %{}
    end

    alter table(:books) do
      add :calibre_id, :integer
      add :calibre_uuid, :string
      # Hash of the mapped Calibre record; a sync rewrites the book when it changes.
      add :calibre_fingerprint, :string
      add :calibre_modified_at, :naive_datetime
      add :sort_title, :string
      add :added_at, :naive_datetime
      # 0–5 stars, halves allowed; the library's rating, not a user's.
      add :rating, :float
    end

    alter table(:series) do
      add :calibre_id, :integer
    end

    alter table(:creators) do
      add :sort_name, :string
    end

    create unique_index(:books, [:library_id, :calibre_id], where: "calibre_id IS NOT NULL")
    create index(:books, [:library_id, :calibre_uuid], where: "calibre_uuid IS NOT NULL")
    create unique_index(:series, [:library_id, :calibre_id], where: "calibre_id IS NOT NULL")
  end
end
