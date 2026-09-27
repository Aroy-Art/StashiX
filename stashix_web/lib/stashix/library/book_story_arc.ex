defmodule Stashix.Library.BookStoryArc do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_story_arcs" do
    field :name, :string
    field :arc_number, :integer
    field :external_id, :string

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(arc, attrs) do
    arc
    |> cast(attrs, [:book_id, :name, :arc_number, :external_id])
    |> validate_required([:book_id, :name])
    |> unique_constraint([:book_id, :name])
  end
end
