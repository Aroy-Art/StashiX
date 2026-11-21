# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateKoboSyncedCollections do
  use Ecto.Migration

  # The collections each Kobo has as shelves, by the app password it syncs
  # with, and a hash of the name and books it was sent: a sync sends the
  # shelves that are new, changed (the hash differs) or gone.
  def change do
    create table(:kobo_synced_collections, primary_key: false) do
      add :app_password_id, references(:app_passwords, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :collection_id, :uuid, null: false, primary_key: true
      add :items_hash, :string, null: false
      add :synced_at, :utc_datetime, null: false
    end
  end
end
