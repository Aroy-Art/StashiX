# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCollectionCover do
  use Ecto.Migration

  # The book whose cover stands for a collection, picked by its owner; none
  # means the first books' covers.
  def change do
    alter table(:collections) do
      add :cover_book_id, references(:books, type: :uuid, on_delete: :nilify_all)
    end
  end
end
