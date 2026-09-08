defmodule Stashix.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :username, :string
    field :display_name, :string
    field :password, :string, virtual: true
    field :password_hash, :string
    field :role, Ecto.Enum, values: [:admin, :user], default: :user
    field :birth_date, :date
    field :reader_settings, :map, default: %{}

    has_many :library_permissions, Stashix.Library.LibraryPermission

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :username, :display_name, :password, :role, :birth_date])
    |> validate_required([:email, :username, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:username, min: 2, max: 50)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:password, min: 8)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> hash_password()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :username, :display_name, :password, :role, :birth_date])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:username, min: 2, max: 50)
    |> validate_length(:display_name, max: 100)
    |> validate_length(:password, min: 8)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> maybe_hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset

  defp maybe_hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))
  end

  defp maybe_hash_password(changeset), do: changeset

  def reader_settings_changeset(user, attrs) do
    cast(user, attrs, [:reader_settings])
  end
end
