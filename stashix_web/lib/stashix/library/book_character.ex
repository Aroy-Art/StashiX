defmodule Stashix.Library.BookCharacter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_characters" do
    field :name, :string
    field :external_id, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(character, attrs) do
    character
    |> cast(attrs, [:book_id, :name, :external_id])
    |> validate_required([:book_id, :name])
    |> unique_constraint([:book_id, :name])
  end
end
