# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCalibrePosition do
  use Ecto.Migration

  # How far Calibre's viewer got in the book (0–1) at the last sync.
  def change do
    alter table(:books) do
      add :calibre_position, :float
    end
  end
end
