defmodule Stashix.Library.BookTag do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_tags" do
    field :name, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:book_id, :name])
    |> validate_required([:book_id, :name])
    |> unique_constraint([:book_id, :name])
  end
end
