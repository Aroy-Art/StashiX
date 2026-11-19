# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateAppPasswords do
  use Ecto.Migration

  # Passwords a user makes for one reading app or device (OPDS clients, and
  # later Kobo sync). Only a SHA-256 of each is kept.
  def change do
    create table(:app_passwords, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :binary, null: false
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:app_passwords, [:token_hash])
    create index(:app_passwords, [:user_id])
  end
end
