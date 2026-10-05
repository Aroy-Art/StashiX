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
end
