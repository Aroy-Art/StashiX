defmodule Stashix.Library.Imprint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "imprints" do
    field :name, :string
    field :source_id, :string

    belongs_to :publisher, Stashix.Library.Publisher

    timestamps()
  end

  def changeset(imprint, attrs) do
    imprint
    |> cast(attrs, [:name, :source_id, :publisher_id])
    |> validate_required([:name, :publisher_id])
    |> unique_constraint([:publisher_id, :name])
  end
end
