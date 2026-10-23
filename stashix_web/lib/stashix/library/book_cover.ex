# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.BookCover do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_covers" do
    field :path, :string
    field :blurhash, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(cover, attrs) do
    cover
    |> cast(attrs, [:path, :blurhash, :book_id])
    |> validate_required([:path, :book_id])
    |> unique_constraint(:book_id)
  end
end
