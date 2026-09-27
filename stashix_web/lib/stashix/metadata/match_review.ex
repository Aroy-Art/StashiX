defmodule Stashix.Metadata.MatchReview do
  @moduledoc """
  A book or series whose automatic match was not confident enough (or failed).
  Holds the search query and scored candidates so an admin can pick one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending resolved skipped failed)

  schema "metadata_match_reviews" do
    field :status, :string, default: "pending"
    field :query, :map, default: %{}
    field :candidates, {:array, :map}, default: []
    field :error, :string

    belongs_to :book, Stashix.Library.Book
    belongs_to :series, Stashix.Library.Series
    belongs_to :library, Stashix.Library.Library

    timestamps()
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [:status, :query, :candidates, :error, :book_id, :series_id, :library_id])
    |> validate_inclusion(:status, @statuses)
  end
end
