defmodule Stashix.Library.BookPrice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_prices" do
    field :amount, :decimal
    # ISO 3166-1 alpha-2 country code (e.g. "US", "CA")
    field :country, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(price, attrs) do
    price
    |> cast(attrs, [:book_id, :amount, :country])
    |> validate_required([:book_id, :amount, :country])
    |> validate_length(:country, is: 2)
    |> unique_constraint([:book_id, :country])
  end
end
