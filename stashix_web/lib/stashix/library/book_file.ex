# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.BookFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_files" do
    field :path, :string
    field :format, Ecto.Enum, values: Stashix.Media.Formats.all()
    field :file_size, :integer, default: 0
    field :file_hash, :string
    field :last_modified, :naive_datetime
    field :page_count, :integer, default: 0
    field :source_format, :string
    # Detected at scan; see `Stashix.Media.ContentKind`.
    field :content_kind, Ecto.Enum, values: [:images, :text]
    field :deleted_at, :naive_datetime

    belongs_to :book, Stashix.Library.Book
    timestamps()
  end

  def changeset(book_file, attrs) do
    book_file
    |> cast(attrs, [
      :path,
      :format,
      :file_size,
      :file_hash,
      :last_modified,
      :page_count,
      :source_format,
      :content_kind,
      :deleted_at,
      :book_id
    ])
    |> validate_required([:path, :format, :book_id])
    |> unique_constraint(:path)
  end
end
