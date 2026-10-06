defmodule Stashix.Accounts do
  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Accounts.{Session, User}
  alias Stashix.Auth.LoginThrottle

  def get_user(id) do
    Repo.get(User, id)
  end

  def get_user!(id) do
    Repo.get!(User, id)
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def list_users do
    Repo.all(User)
  end

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a user. The last admin cannot be demoted."
  def update_user(user, attrs) do
    changeset = User.update_changeset(user, attrs)

    if Ecto.Changeset.get_field(changeset, :role) != :admin and last_admin?(user) do
      {:error, Ecto.Changeset.add_error(changeset, :role, "cannot demote the last admin")}
    else
      with {:ok, updated} <- Repo.update(changeset) do
        if updated.token_version != user.token_version, do: disconnect_sessions(updated.id)
        {:ok, updated}
      end
    end
  end

  @doc """
  Deletes a user. The last admin cannot be deleted: with no users left, setup
  would be open to anyone again.
  """
  def delete_user(user) do
    if last_admin?(user) do
      {:error, :last_admin}
    else
      with {:ok, deleted} <- Repo.delete(user) do
        disconnect_sessions(deleted.id)
        {:ok, deleted}
      end
    end
  end

  @doc "Topic stored as `live_socket_id` in a user's browser sessions."
  def session_topic(user_id), do: "users_sessions:#{user_id}"

  @doc """
  Closes the user's open LiveView sockets. They reconnect and mount again, so
  a change to the account or its permissions applies right away.
  """
  def disconnect_sessions(user_id) do
    topic = session_topic(user_id)

    Phoenix.PubSub.broadcast(Stashix.PubSub, topic, %Phoenix.Socket.Broadcast{
      topic: topic,
      event: "disconnect",
      payload: %{}
    })
  end

  # ---------------------------------------------------------------------------
  # Sessions: a record of each sign-in, for the list under Settings > Security.
  # ---------------------------------------------------------------------------

  # As long as a refresh token lives; see Stashix.Auth.TokenHelper.
  @session_ttl 7 * 24 * 60 * 60
  # How stale `last_seen_at` may get before a page load writes it again.
  @session_touch_interval 5 * 60

  @doc "Records a sign-in. Rows of the user that are no longer live are cleared on the way."
  def create_session(%User{} = user, user_agent) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    Repo.delete_all(
      from s in Session,
        where: s.user_id == ^user.id and (s.expires_at <= ^now or s.token_version != ^user.token_version)
    )

    Repo.insert(%Session{
      user_id: user.id,
      user_agent: user_agent && String.slice(user_agent, 0, 500),
      token_version: user.token_version,
      last_seen_at: now,
      expires_at: DateTime.add(now, @session_ttl)
    })
  end

  @doc "The user's live sessions, most recently used first."
  def list_sessions(%User{} = user) do
    now = DateTime.utc_now()

    Repo.all(
      from s in Session,
        where: s.user_id == ^user.id and s.token_version == ^user.token_version and s.expires_at > ^now,
        order_by: [desc: s.last_seen_at, desc: s.inserted_at]
    )
  end

  @doc """
  Marks a session as in use now. Writes at most once per few minutes, so it is
  cheap to call on every page load. With `extend: true` it always writes and
  also pushes the expiry out, for when the client was handed a new refresh
  token.
  """
  def touch_session(id, opts \\ [])
  def touch_session(nil, _opts), do: :ok

  def touch_session(id, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    if opts[:extend] do
      Repo.update_all(from(s in Session, where: s.id == ^id),
        set: [last_seen_at: now, expires_at: DateTime.add(now, @session_ttl)]
      )
    else
      stale = DateTime.add(now, -@session_touch_interval)
      Repo.update_all(from(s in Session, where: s.id == ^id and s.last_seen_at < ^stale), set: [last_seen_at: now])
    end

    :ok
  end

  @doc "Ends a session, on sign-out: its tokens stop working."
  def delete_session(nil), do: :ok

  def delete_session(id) do
    Repo.delete_all(from s in Session, where: s.id == ^id)
    :ok
  end

  @doc """
  Signs one of the user's sessions out. Their open sockets are closed so the
  one that just lost its session lands on the login page; the others
  reconnect. Returns `{:error, :not_found}` for a session that is not theirs.
  """
  def revoke_session(%User{} = user, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, _} <- Repo.delete_all(from s in Session, where: s.id == ^id and s.user_id == ^user.id) do
      disconnect_sessions(user.id)
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Whether tokens of this session still count. Tokens without one (nil) always do."
  def session_open?(nil), do: true
  def session_open?(id), do: Repo.exists?(from s in Session, where: s.id == ^id)

  defp last_admin?(%User{role: :admin, id: id}) do
    not Repo.exists?(from(u in User, where: u.role == :admin and u.id != ^id))
  end

  defp last_admin?(_user), do: false

  @doc """
  Checks a login (email or username) and password. Returns
  `{:error, :rate_limited}` without checking once the login has had too many
  failed attempts (see `Stashix.Auth.LoginThrottle`).
  """
  def authenticate_user(login, password) do
    if LoginThrottle.blocked?(login) do
      {:error, :rate_limited}
    else
      user =
        if String.contains?(login, "@"),
          do: get_user_by_email(login),
          else: get_user_by_username(login)

      cond do
        user && Bcrypt.verify_pass(password, user.password_hash) ->
          LoginThrottle.clear(login)
          {:ok, user}

        user ->
          LoginThrottle.record_failure(login)
          {:error, :invalid_password}

        true ->
          Bcrypt.no_user_verify()
          LoginThrottle.record_failure(login)
          {:error, :not_found}
      end
    end
  end

  def save_reader_settings(user, settings) do
    user
    |> User.reader_settings_changeset(%{reader_settings: settings})
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Self-service: what a signed-in user may change about their own account.
  # Kept apart from update_user/2, which is the admin path and can set a role.
  # ---------------------------------------------------------------------------

  @doc "Updates appearance settings, e.g. `%{\"read_mark\" => \"stamp\"}`."
  def update_ui_settings(%User{} = user, attrs) do
    user |> User.ui_settings_changeset(attrs) |> Repo.update()
  end

  @doc "Updates display name, username and birth date."
  def update_profile(%User{} = user, attrs) do
    user |> User.profile_changeset(attrs) |> Repo.update()
  end

  @doc """
  Changes the email address after checking the current password. Returns
  `{:error, :invalid_password}` when it does not match and
  `{:error, :rate_limited}` after too many wrong guesses.
  """
  def change_email(%User{} = user, current_password, attrs) do
    with :ok <- verify_password(user, current_password) do
      user |> User.email_changeset(attrs) |> Repo.update()
    end
  end

  @doc """
  Changes the password after checking the current one. Every token issued
  before is revoked and open LiveView sockets are closed; the caller issues
  fresh tokens for the session that made the change.
  """
  def change_password(%User{} = user, current_password, attrs) do
    with :ok <- verify_password(user, current_password),
         {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
      disconnect_sessions(updated.id)
      {:ok, updated}
    end
  end

  @doc """
  Signs the user out everywhere: revokes every token and closes open
  sockets. The caller issues fresh tokens for the session it wants to keep.
  """
  def revoke_sessions(%User{} = user) do
    with {:ok, updated} <- user |> User.revoke_tokens_changeset() |> Repo.update() do
      disconnect_sessions(updated.id)
      {:ok, updated}
    end
  end

  # Wrong guesses are throttled like logins, under a key of their own so that
  # someone holding a stolen session cannot lock the owner out of signing in.
  defp verify_password(%User{id: id, password_hash: hash}, password) when is_binary(password) do
    key = "settings:#{id}"

    cond do
      LoginThrottle.blocked?(key) ->
        {:error, :rate_limited}

      Bcrypt.verify_pass(password, hash) ->
        LoginThrottle.clear(key)
        :ok

      true ->
        LoginThrottle.record_failure(key)
        {:error, :invalid_password}
    end
  end

  defp verify_password(_user, _password), do: {:error, :invalid_password}

  def setup_complete? do
    Repo.aggregate(User, :count, :id) > 0
  end
end
