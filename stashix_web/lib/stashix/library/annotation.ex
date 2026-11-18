# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.Annotation do
  @moduledoc """
  A highlight, note or bookmark a user made in a book (see
  `Stashix.Annotations`).

  - highlight: quoted text (`text`) or an image region, in a `color`, maybe
    with a `note`
  - note: like a highlight, but the note is the point (no colour shown)
  - bookmark: a spot, no text

  `locator` is a `Stashix.Library.Locator`; `progression` (0..1) orders
  annotations through the book. `preview` is the file name of an image
  region's cropped picture.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @kinds [:highlight, :note, :bookmark]
  @colors ~w(yellow green blue pink)
  @max_text 10_000

  def colors, do: @colors

  schema "annotations" do
    field :kind, Ecto.Enum, values: @kinds
    field :color, :string
    field :locator, :map
    field :progression, :float, default: 0.0
    field :text, :string
    field :note, :string
    field :preview, :string

    belongs_to :user, Stashix.Accounts.User
    belongs_to :book, Stashix.Library.Book
    belongs_to :book_file, Stashix.Library.BookFile

    timestamps(type: :utc_datetime)
  end

  def create_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:kind, :color, :locator, :progression, :text, :note, :user_id, :book_id, :book_file_id])
    |> validate_required([:kind, :locator, :user_id, :book_id])
    |> common()
  end

  @doc "What can change once made: colour and note."
  def update_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:color, :note])
    |> common()
  end

  defp common(changeset) do
    changeset
    |> update_change(:note, &blank_to_nil/1)
    |> update_change(:text, &blank_to_nil/1)
    |> validate_inclusion(:color, @colors)
    |> validate_number(:progression, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:text, max: @max_text)
    |> validate_length(:note, max: @max_text)
  end

  defp blank_to_nil(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
  defp blank_to_nil(s), do: s
end
