# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddBookTitleTrigram do
  use Ecto.Migration

  # Trigram word similarity on titles backs partial-word and typo matches in
  # book search, next to the full-text search_vec. pg_trgm is a trusted
  # extension, so the database owner can create it.
  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    execute "CREATE INDEX books_title_trgm_gin ON books USING gin (title gin_trgm_ops)"
  end

  def down do
    execute "DROP INDEX books_title_trgm_gin"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
