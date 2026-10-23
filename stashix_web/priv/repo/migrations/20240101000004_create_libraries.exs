# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateLibraries do
  use Ecto.Migration

  def change do
    create table(:libraries, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :root_path, :string, null: false
      add :standalone_folders, :jsonb, default: "[]"

      timestamps()
    end

    create unique_index(:libraries, [:root_path])
  end
end
