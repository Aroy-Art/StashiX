# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.Collection do
  @moduledoc """
  A user's named group of books and whole series (see `Stashix.Collections`
  and docs/collections-plan.md).

  One owner (`user_id`) edits it; `shared` lets every user see it, read-only
  and limited to the books they may read. Names are unique per owner,
  ignoring case. `default_sort` is how it opens: its own order
  (`"position"`), or by title, year or date added. `kind` / `rules` are for
  smart collections later; every collection is `"manual"` for now.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sorts ~w(position title year added)

  def sorts, do: @sorts

  schema "collections" do
    field :name, :string
    field :description, :string
    field :shared, :boolean, default: false
    field :kind, :string, default: "manual"
    field :rules, :map
    field :default_sort, :string, default: "position"

    belongs_to :user, Stashix.Accounts.User
    has_many :entries, Stashix.Library.CollectionEntry

    timestamps(type: :utc_datetime)
  end

  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:name, :description, :shared, :default_sort])
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 4000)
    |> validate_inclusion(:default_sort, @sorts)
    |> unique_constraint(:name,
      name: :collections_user_id_name_index,
      message: "you already have a collection with this name"
    )
  end

  defp blank_to_nil(text) do
    case text && String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
