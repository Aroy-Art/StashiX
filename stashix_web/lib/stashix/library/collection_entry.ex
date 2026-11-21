# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.CollectionEntry do
  @moduledoc """
  One place in a `Stashix.Library.Collection`: a book, or a whole series
  (whose books, now and later, all count as in the collection). `position`
  orders entries; positions leave gaps so a move rarely touches others.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "collection_entries" do
    field :position, :integer

    belongs_to :collection, Stashix.Library.Collection
    belongs_to :book, Stashix.Library.Book
    belongs_to :series, Stashix.Library.Series

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
