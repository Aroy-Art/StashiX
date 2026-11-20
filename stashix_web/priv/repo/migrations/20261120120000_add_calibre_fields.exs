# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCalibreFields do
  use Ecto.Migration

  # A Calibre book's custom column values, by column label:
  # `%{"read" => %{"name" => "Read", "type" => "bool", "value" => true}}`.
  def change do
    alter table(:books) do
      add :calibre_fields, :map, null: false, default: %{}
    end
  end
end
