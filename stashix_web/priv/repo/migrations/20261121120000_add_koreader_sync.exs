# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddKoreaderSync do
  use Ecto.Migration

  # KOReader names a book by a partial MD5 of its file (`koreader_hash`),
  # filled in lazily; `koreader_hash_of` is the `file_hash` it was taken
  # from, so a changed file gets a new one. KOReader signs in with an MD5 of
  # the password, so app passwords keep a SHA-256 of that too.
  def change do
    alter table(:book_files) do
      add :koreader_hash, :string
      add :koreader_hash_of, :string
    end

    create index(:book_files, [:koreader_hash])

    alter table(:app_passwords) do
      add :koreader_key, :binary
    end

    create index(:app_passwords, [:koreader_key])
  end
end
