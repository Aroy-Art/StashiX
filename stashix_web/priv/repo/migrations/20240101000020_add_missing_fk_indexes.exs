# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Repo.Migrations.AddMissingFkIndexes do
  use Ecto.Migration

  def change do
    create index(:book_credits, [:creator_id])
    create index(:library_permissions, [:library_id])
    create index(:reading_progress, [:book_id])
    create index(:series, [:publisher_id])
    create index(:books, [:publisher_id])
    create index(:books, [:imprint_id])
  end
end
