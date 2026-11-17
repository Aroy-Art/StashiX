# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddContentKind do
  use Ecto.Migration

  # Whether a file reads as page images (comics, scans) or as text. The file's
  # value is detected at scan; the book's is the user's override, which scans
  # never touch. Null on both means images, as before.
  def change do
    alter table(:book_files) do
      add :content_kind, :string
    end

    alter table(:books) do
      add :content_kind, :string
    end
  end
end
