defmodule Stashix.Library.Creator do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "creators" do
    field :name, :string

    has_many :credits, Stashix.Library.BookCredit

    timestamps()
  end

  def changeset(creator, attrs) do
    creator
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
