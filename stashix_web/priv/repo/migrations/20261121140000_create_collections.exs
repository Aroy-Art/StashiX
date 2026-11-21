# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  # A user's collections of books and whole series (docs/collections-plan.md).
  # `kind` and `rules` are for smart collections later. Entries hold one book
  # or one series each, ordered by `position` (gaps of 1024).
  def change do
    create table(:collections, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :shared, :boolean, null: false, default: false
      add :kind, :string, null: false, default: "manual"
      add :rules, :map
      add :default_sort, :string, null: false, default: "position"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:collections, ["user_id", "lower(name)"], name: :collections_user_id_name_index)
    create index(:collections, [:shared])

    create table(:collection_entries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :collection_id, references(:collections, type: :uuid, on_delete: :delete_all), null: false
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all)
      add :series_id, references(:series, type: :uuid, on_delete: :delete_all)
      add :position, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create constraint(:collection_entries, :one_item, check: "(book_id IS NULL) <> (series_id IS NULL)")

    create unique_index(:collection_entries, [:collection_id, :book_id], where: "book_id IS NOT NULL")
    create unique_index(:collection_entries, [:collection_id, :series_id], where: "series_id IS NOT NULL")
    create index(:collection_entries, [:collection_id, :position])
    create index(:collection_entries, [:book_id])
    create index(:collection_entries, [:series_id])
  end
end
