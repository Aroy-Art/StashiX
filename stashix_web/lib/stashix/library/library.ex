# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.Library do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds [:comics, :books]
  @sources [:folders, :calibre]

  schema "libraries" do
    field :name, :string
    # Comics/manga or books: sets defaults (reader, metadata matching, labels)
    # and which libraries the browse switcher shows.
    field :kind, Ecto.Enum, values: @kinds, default: :comics
    # Where books come from: a folder scan, or a Calibre `metadata.db` at the
    # root (see `Stashix.Calibre`).
    field :source, Ecto.Enum, values: @sources, default: :folders
    field :calibre_state, :map, default: %{}
    # "read_user_id" and "read_column": whose read status a custom column holds.
    field :calibre_settings, :map, default: %{}
    field :root_path, :string
    field :standalone_folders, {:array, :string}, default: []

    has_many :books, Stashix.Library.Book
    has_many :series, Stashix.Library.Series
    has_many :permissions, Stashix.Library.LibraryPermission

    timestamps()
  end

  @doc "The library kinds, in switcher order."
  def kinds, do: @kinds

  def sources, do: @sources

  def changeset(library, attrs) do
    library
    |> cast(attrs, [:name, :root_path, :kind, :source, :standalone_folders, :calibre_settings])
    |> validate_required([:name, :root_path])
    |> unique_constraint(:root_path)
  end
end
