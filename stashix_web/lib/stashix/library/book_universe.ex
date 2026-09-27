defmodule Stashix.Library.BookUniverse do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_universes" do
    field :name, :string
    field :designation, :string
    field :external_id, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(universe, attrs) do
    universe
    |> cast(attrs, [:book_id, :name, :designation, :external_id])
    |> validate_required([:book_id, :name])
    |> unique_constraint([:book_id, :name])
  end
end
