defmodule Stashix.AccountsTest do
  use Stashix.DataCase, async: false

  alias Stashix.Accounts
  alias Stashix.Auth.{LoginThrottle, TokenHelper}

  defp user(name, attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user(Map.merge(%{email: "#{name}@example.com", username: name, password: "password1234"}, attrs))

    user
  end

  describe "token revocation" do
    test "changing the password or role invalidates earlier tokens" do
      user = user("revoke")
      {:ok, access, refresh} = TokenHelper.generate_tokens(user)
      assert {:ok, _} = TokenHelper.resource_from_token(access)

      {:ok, user} = Accounts.update_user(user, %{password: "another-password"})
      assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
      assert {:error, :token_revoked} = TokenHelper.refresh_tokens(refresh)

      {:ok, access, _refresh} = TokenHelper.generate_tokens(user)
      assert {:ok, _} = TokenHelper.resource_from_token(access)

      {:ok, _} = Accounts.update_user(user, %{role: :admin})
      assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
    end

    test "other profile changes keep tokens valid" do
      user = user("keep")
      {:ok, access, _refresh} = TokenHelper.generate_tokens(user)

      {:ok, _} = Accounts.update_user(user, %{display_name: "Keep"})
      assert {:ok, _} = TokenHelper.resource_from_token(access)
    end
  end

  describe "sessions" do
    alias Stashix.Accounts.Session

    test "are listed while live: not expired and not revoked" do
      user = user("sessions")
      {:ok, kept} = Accounts.create_session(user, "Mozilla/5.0 (X11; Linux x86_64) Firefox/130.0")
      {:ok, expired} = Accounts.create_session(user, nil)

      Repo.update_all(from(s in Session, where: s.id == ^expired.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -60)]
      )

      assert [%Session{id: id}] = Accounts.list_sessions(user)
      assert id == kept.id

      {:ok, user} = Accounts.revoke_sessions(user)
      assert [] = Accounts.list_sessions(user)

      # The next sign-in clears the dead rows.
      {:ok, fresh} = Accounts.create_session(user, nil)
      assert [fresh.id] == Repo.all(from s in Session, where: s.user_id == ^user.id, select: s.id)
    end

    test "touching writes last_seen_at only once it has gone stale" do
      user = user("touch")
      {:ok, session} = Accounts.create_session(user, nil)
      old = DateTime.add(session.last_seen_at, -3600)

      Accounts.touch_session(session.id)
      assert Repo.get!(Session, session.id).last_seen_at == session.last_seen_at

      Repo.update_all(from(s in Session, where: s.id == ^session.id), set: [last_seen_at: old, expires_at: old])
      Accounts.touch_session(session.id)
      touched = Repo.get!(Session, session.id)
      assert DateTime.compare(touched.last_seen_at, old) == :gt
      assert touched.expires_at == old

      Accounts.touch_session(session.id, extend: true)
      assert DateTime.compare(Repo.get!(Session, session.id).expires_at, DateTime.utc_now()) == :gt
      assert :ok = Accounts.touch_session(nil)
    end

    test "a refresh keeps the session of the token it replaces" do
      user = user("refresh")
      {:ok, _access, refresh, session_id} = TokenHelper.start_session(user, "okhttp/4.12")
      {:ok, _user, _access, new_refresh} = TokenHelper.refresh_tokens(refresh)

      assert {:ok, %{"sid" => ^session_id}} = TokenHelper.verify_refresh_token(new_refresh)
      assert [%Session{id: ^session_id} = session] = Accounts.list_sessions(user)
      assert Session.device(session) == "okhttp/4.12"
    end

    test "device names" do
      for {user_agent, name} <- [
            {"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128.0 Safari/537.36 Edg/128.0",
             "Edge on Windows"},
            {"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.5 Safari/605.1.15",
             "Safari on macOS"},
            {"Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 Version/17.5 Mobile/15E148 Safari/604.1",
             "Safari on iPhone"},
            {nil, "Unknown device"}
          ] do
        assert Session.device(%Session{user_agent: user_agent}) == name
      end
    end
  end

  describe "last admin" do
    test "cannot be deleted or demoted" do
      admin = user("boss", %{role: :admin})

      assert {:error, :last_admin} = Accounts.delete_user(admin)
      assert {:error, changeset} = Accounts.update_user(admin, %{role: :user})
      assert %{role: ["cannot demote the last admin"]} = errors_on(changeset)
      assert {:ok, _} = Accounts.update_user(admin, %{display_name: "Boss"})
    end

    test "can be removed once another admin exists" do
      admin = user("boss", %{role: :admin})
      other = user("deputy", %{role: :admin})

      assert {:ok, other} = Accounts.update_user(other, %{role: :user})
      assert {:error, :last_admin} = Accounts.delete_user(admin)

      assert {:ok, %{role: :admin}} = Accounts.update_user(other, %{role: :admin})
      assert {:ok, _} = Accounts.delete_user(admin)
    end
  end

  describe "login throttling" do
    test "refuses further attempts after repeated failures, even with the right password" do
      user("throttled")
      on_exit(fn -> LoginThrottle.clear("throttled") end)

      for _ <- 1..10, do: assert({:error, :invalid_password} = Accounts.authenticate_user("throttled", "wrong"))

      assert {:error, :rate_limited} = Accounts.authenticate_user("throttled", "password1234")
      assert {:error, :rate_limited} = Accounts.authenticate_user(" Throttled ", "password1234")
    end

    test "a successful login clears the count" do
      user("forgetful")
      on_exit(fn -> LoginThrottle.clear("forgetful") end)

      for _ <- 1..9, do: Accounts.authenticate_user("forgetful", "wrong")
      assert {:ok, _} = Accounts.authenticate_user("forgetful", "password1234")

      for _ <- 1..9, do: Accounts.authenticate_user("forgetful", "wrong")
      assert {:ok, _} = Accounts.authenticate_user("forgetful", "password1234")
    end
  end

  describe "self-service changes" do
    test "appearance settings accept known choices only" do
      user = user("looks")
      assert Accounts.User.ui_setting(user, "read_mark") == "check"

      assert {:ok, user} = Accounts.update_ui_settings(user, %{"read_mark" => "stamp"})
      assert Accounts.User.ui_setting(user, "read_mark") == "stamp"

      assert {:error, _} = Accounts.update_ui_settings(user, %{"read_mark" => "sparkles"})
      assert {:error, _} = Accounts.update_ui_settings(user, %{"role" => "admin"})
      assert Accounts.User.ui_setting(Accounts.get_user!(user.id), "read_mark") == "stamp"
    end

    test "a stored value that is no longer a choice falls back to the default" do
      user = %{user("stale") | ui_settings: %{"read_mark" => "retired"}}
      assert Accounts.User.ui_setting(user, "read_mark") == "check"
    end

    test "the profile cannot carry a role, an email or a password" do
      user = user("plain")

      assert {:ok, updated} =
               Accounts.update_profile(user, %{
                 "display_name" => "Plain Jane",
                 "role" => "admin",
                 "email" => "other@example.com",
                 "password" => "sneaky-password"
               })

      assert updated.display_name == "Plain Jane"
      assert updated.role == :user
      assert updated.email == "plain@example.com"
      assert updated.password_hash == user.password_hash
      assert updated.token_version == user.token_version
    end

    test "the profile rejects a taken username and a birth date in the future" do
      user("taken")
      user = user("mine")

      assert {:error, changeset} = Accounts.update_profile(user, %{"username" => "taken"})
      assert %{username: [_]} = errors_on(changeset)

      assert {:error, changeset} = Accounts.update_profile(user, %{"birth_date" => Date.add(Date.utc_today(), 1)})
      assert %{birth_date: ["cannot be in the future"]} = errors_on(changeset)
    end

    test "changing the password needs the current one and revokes earlier tokens" do
      user = user("secret")
      on_exit(fn -> LoginThrottle.clear("settings:#{user.id}") end)
      {:ok, access, refresh} = TokenHelper.generate_tokens(user)
      new = %{"password" => "a-new-password", "password_confirmation" => "a-new-password"}

      assert {:error, :invalid_password} = Accounts.change_password(user, "wrong", new)
      assert {:error, :invalid_password} = Accounts.change_password(user, nil, new)
      assert {:ok, _} = TokenHelper.resource_from_token(access)

      assert {:error, changeset} =
               Accounts.change_password(user, "password1234", %{new | "password_confirmation" => "different"})

      assert %{password_confirmation: ["does not match"]} = errors_on(changeset)

      assert {:error, changeset} =
               Accounts.change_password(user, "password1234", %{
                 "password" => "short",
                 "password_confirmation" => "short"
               })

      assert %{password: [_]} = errors_on(changeset)

      assert {:ok, _} = Accounts.change_password(user, "password1234", new)
      assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
      assert {:error, :token_revoked} = TokenHelper.refresh_tokens(refresh)
      assert {:error, :invalid_password} = Accounts.authenticate_user("secret", "password1234")
      assert {:ok, _} = Accounts.authenticate_user("secret", "a-new-password")
    end

    test "wrong guesses at the current password are throttled without locking the login" do
      user = user("guessed")
      on_exit(fn -> LoginThrottle.clear("settings:#{user.id}") end)
      new = %{"password" => "a-new-password", "password_confirmation" => "a-new-password"}

      for _ <- 1..10, do: assert({:error, :invalid_password} = Accounts.change_password(user, "wrong", new))

      assert {:error, :rate_limited} = Accounts.change_password(user, "password1234", new)
      assert {:ok, _} = Accounts.authenticate_user("guessed", "password1234")
    end

    test "changing the email needs the current password and keeps tokens valid" do
      user = user("mover")
      on_exit(fn -> LoginThrottle.clear("settings:#{user.id}") end)
      {:ok, access, _refresh} = TokenHelper.generate_tokens(user)

      assert {:error, :invalid_password} = Accounts.change_email(user, "wrong", %{"email" => "new@example.com"})
      assert {:error, changeset} = Accounts.change_email(user, "password1234", %{"email" => "not-an-email"})
      assert %{email: [_]} = errors_on(changeset)

      assert {:ok, updated} = Accounts.change_email(user, "password1234", %{"email" => "New@Example.com"})
      assert updated.email == "new@example.com"
      assert {:ok, _} = TokenHelper.resource_from_token(access)
    end

    test "signing out everywhere revokes earlier tokens" do
      user = user("everywhere")
      {:ok, access, _refresh} = TokenHelper.generate_tokens(user)

      assert {:ok, updated} = Accounts.revoke_sessions(user)
      assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)

      {:ok, fresh, _} = TokenHelper.generate_tokens(updated)
      assert {:ok, _} = TokenHelper.resource_from_token(fresh)
    end
  end
end
