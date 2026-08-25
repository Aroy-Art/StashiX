defmodule Stashix.Library.Library do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "libraries" do
    field :name, :string
    field :root_path, :string
    field :standalone_folders, {:array, :string}, default: []

    has_many :books, Stashix.Library.Book
    has_many :series, Stashix.Library.Series
    has_many :permissions, Stashix.Library.LibraryPermission

    timestamps()
  end

  def changeset(library, attrs) do
    library
    |> cast(attrs, [:name, :root_path, :standalone_folders])
    |> validate_required([:name, :root_path])
    |> unique_constraint(:root_path)
  end
end
