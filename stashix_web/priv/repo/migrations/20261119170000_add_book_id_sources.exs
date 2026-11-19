# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddBookIdSources do
  use Ecto.Migration

  # Book identifiers Calibre keeps (`Stashix.Calibre.Mapper`).
  @sources ["Google Books", "Amazon", "Goodreads", "Open Library", "ISSN", "DOI"]

  def up do
    for source <- @sources do
      execute "ALTER TYPE information_source ADD VALUE IF NOT EXISTS '#{source}'"
    end
  end

  # Postgres can't drop enum values; the extra ones are harmless.
  def down, do: :ok
end
