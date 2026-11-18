# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.CreateAnnotations do
  use Ecto.Migration

  # A user's highlights, notes and bookmarks in a book. `locator` says where
  # (the reading-progress shape plus a CFI range, PDF text rects or an image
  # region); `progression` orders them through the book. An image region
  # keeps a cropped picture of itself at `preview`.
  def change do
    create table(:annotations, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :book_id, references(:books, type: :uuid, on_delete: :delete_all), null: false
      add :book_file_id, references(:book_files, type: :uuid, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :color, :string
      add :locator, :map, null: false
      add :progression, :float, null: false, default: 0.0
      add :text, :text
      add :note, :text
      add :preview, :string

      timestamps(type: :utc_datetime)
    end

    create index(:annotations, [:user_id, :book_id, :progression])
    create index(:annotations, [:book_id])
  end
end
