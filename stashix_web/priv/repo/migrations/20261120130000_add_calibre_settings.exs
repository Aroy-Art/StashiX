# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCalibreSettings do
  use Ecto.Migration

  # A Calibre library's own settings, e.g. which user a custom column's read
  # status belongs to: %{"read_user_id" => …, "read_column" => "read"}.
  def change do
    alter table(:libraries) do
      add :calibre_settings, :map, null: false, default: %{}
    end
  end
end
