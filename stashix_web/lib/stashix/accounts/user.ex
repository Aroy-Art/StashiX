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
    # Appearance choices; see @ui_defaults for the keys and ui_setting/2 to read one.
    field :ui_settings, :map, default: %{}
    # Embedded in issued tokens; bumping it revokes every token issued before.
    field :token_version, :integer, default: 0

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
    |> revoke_tokens_on_credential_change()
  end

  defp revoke_tokens_on_credential_change(%Ecto.Changeset{valid?: true} = changeset) do
    if changed?(changeset, :password_hash) or changed?(changeset, :role) do
      put_change(changeset, :token_version, changeset.data.token_version + 1)
    else
      changeset
    end
  end

  defp revoke_tokens_on_credential_change(changeset), do: changeset

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

  # ---------------------------------------------------------------------------
  # Changes a user makes to their own account. None of these cast :role.
  # ---------------------------------------------------------------------------

  @ui_defaults %{"read_mark" => "check"}
  @ui_choices %{"read_mark" => ~w(check stamp)}

  @doc "Allowed values per appearance setting."
  def ui_choices, do: @ui_choices

  @doc "An appearance setting of the user, falling back to its default."
  def ui_setting(%__MODULE__{ui_settings: settings}, key) when is_map_key(@ui_defaults, key) do
    value = Map.get(settings || %{}, key)
    if value in Map.fetch!(@ui_choices, key), do: value, else: Map.fetch!(@ui_defaults, key)
  end

  @doc "Merges known appearance keys into the stored settings; unknown keys and values are rejected."
  def ui_settings_changeset(user, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    changeset = change(user)

    case Enum.find(attrs, fn {key, value} -> value not in Map.get(@ui_choices, key, []) end) do
      nil -> put_change(changeset, :ui_settings, Map.merge(user.ui_settings || %{}, attrs))
      {key, _value} -> add_error(changeset, :ui_settings, "has an invalid value for #{key}")
    end
  end

  @doc "Name, login name and birth date."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :display_name, :birth_date])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 50)
    |> validate_length(:display_name, max: 100)
    |> validate_change(:birth_date, fn :birth_date, date ->
      if Date.compare(date, Date.utc_today()) == :gt, do: [birth_date: "cannot be in the future"], else: []
    end)
    |> unique_constraint(:username)
  end

  @doc "New email address. The caller checks the current password first."
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
  end

  @doc """
  New password, confirmed. Bumps the token version, which revokes every token
  issued before. The caller checks the current password first.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> validate_confirmation(:password, message: "does not match")
    |> maybe_hash_password()
    |> revoke_tokens_on_credential_change()
  end

  @doc "Revokes every token issued so far without changing anything else."
  def revoke_tokens_changeset(user), do: change(user, token_version: user.token_version + 1)
end
