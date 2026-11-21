# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateKoboSyncedBooks do
  use Ecto.Migration

  # The books each Kobo has been sent, by the app password it syncs with,
  # and when: the next sync sends what was added, changed or removed since.
  def change do
    create table(:kobo_synced_books, primary_key: false) do
      add :app_password_id, references(:app_passwords, type: :uuid, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false, primary_key: true
      add :synced_at, :utc_datetime, null: false
    end
  end
end
