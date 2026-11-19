# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddLibraryKind do
  use Ecto.Migration

  # Comics/manga or books (novels, non-fiction): sets the defaults a library
  # starts from and which libraries the browse switcher shows.
  def change do
    alter table(:libraries) do
      add :kind, :string, null: false, default: "comics"
    end
  end
end
