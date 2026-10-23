# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddBlurhashToBookCovers do
  use Ecto.Migration

  def change do
    alter table(:book_covers) do
      add :blurhash, :string
    end
  end
end
