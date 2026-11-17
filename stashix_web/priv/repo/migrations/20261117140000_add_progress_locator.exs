# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddProgressLocator do
  use Ecto.Migration

  # Where in a book the reader is, beyond a page index: an EPUB CFI, a PDF
  # page, an image page (`locator`), and how far through the book that is as
  # 0..1 (`progression`), which read status, progress bars and continue
  # reading use. The last page of a book is 1.0, as `current_page` at
  # `page_count - 1` was.
  def up do
    alter table(:reading_progress) do
      add :locator, :map
      add :progression, :float, null: false, default: 0.0
    end

    execute """
    UPDATE reading_progress rp
    SET progression = CASE
      WHEN rp.current_page <= 0 THEN 0.0
      WHEN b.page_count <= 1 THEN 1.0
      ELSE LEAST(rp.current_page::float / (b.page_count - 1), 1.0)
    END
    FROM books b
    WHERE b.id = rp.book_id
    """

    create index(:reading_progress, [:user_id, :progression])
  end

  def down do
    drop index(:reading_progress, [:user_id, :progression])

    alter table(:reading_progress) do
      remove :locator
      remove :progression
    end
  end
end
