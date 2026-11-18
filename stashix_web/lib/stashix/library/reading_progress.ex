# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.ReadingProgress do
  @moduledoc """
  A user's place in a book.

  `current_page` is the page index (EPUB: foliate-js location). `progression`
  is how far through the book that is, 0..1, with the last page at 1.0: it is
  what read status, progress bars and continue reading go by. `locator` says
  exactly where (see `Stashix.Library.Locator`), with `"progression"` too
  (the Readium locator shape, for OPDS and Kobo sync later).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reading_progress" do
    field :current_page, :integer, default: 0
    field :progression, :float, default: 0.0
    field :locator, :map
    field :updated_at, :naive_datetime

    belongs_to :user, Stashix.Accounts.User
    belongs_to :book, Stashix.Library.Book
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:current_page, :progression, :locator, :user_id, :book_id, :updated_at])
    |> validate_required([:current_page, :user_id, :book_id])
    |> validate_number(:progression, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint([:user_id, :book_id])
  end

  @doc """
  `Stashix.Library.update_progress/5` options from client params
  (`"locator"`, `"progression"`), keeping only what fits
  `Stashix.Library.Locator`.
  """
  @spec opts_from_params(map()) :: keyword()
  def opts_from_params(params) do
    [locator: Stashix.Library.Locator.from_params(params["locator"]), progression: params["progression"]]
    |> Enum.filter(fn {_, v} -> is_number(v) or is_map(v) end)
  end

  @doc "How far through a book of `page_count` pages page index `page` is."
  @spec progression(integer(), integer() | nil) :: float()
  def progression(page, _count) when page <= 0, do: 0.0
  def progression(_page, count) when not is_integer(count) or count <= 1, do: 1.0
  def progression(page, count), do: min(page / (count - 1), 1.0)
end
