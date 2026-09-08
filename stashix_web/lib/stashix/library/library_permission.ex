defmodule Stashix.Library.LibraryPermission do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @age_ratings [:unknown, :everyone, :teen, :teen_plus, :mature, :adult, :explicit]

  schema "library_permissions" do
    field :can_read, :boolean, default: true
    field :max_age_rating, Ecto.Enum, values: @age_ratings, default: :everyone

    belongs_to :user, Stashix.Accounts.User
    belongs_to :library, Stashix.Library.Library

    timestamps()
  end

  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:can_read, :max_age_rating, :user_id, :library_id])
    |> validate_required([:user_id, :library_id])
    |> unique_constraint([:user_id, :library_id])
  end
end
