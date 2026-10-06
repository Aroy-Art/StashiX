defmodule StashixWeb.SettingsLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.Accounts
  alias Stashix.Accounts.User
  alias Stashix.Auth.{LoginThrottle, TokenHelper}

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "sam@example.com", username: "sam", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    on_exit(fn -> LoginThrottle.clear("settings:#{user.id}") end)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    %{conn: conn, user: user, access: access}
  end

  test "signed-out visitors are sent to the login page", %{} do
    conn = Plug.Test.init_test_session(build_conn(), %{})
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/settings")
    assert redirected_to(post(conn, ~p"/settings/password", %{})) == "/login"
    assert redirected_to(post(conn, ~p"/settings/sessions/revoke", %{})) == "/login"
  end

  test "the UI tab stores the read mark and publishes it to the layout", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/settings")
    assert html =~ ~s(data-read-mark="check")

    html = view |> element("#ui-settings") |> render_change(%{"read_mark" => "stamp"})
    assert html =~ ~s(data-read-mark="stamp")
    assert User.ui_setting(Accounts.get_user!(user.id), "read_mark") == "stamp"

    view |> element("#ui-settings") |> render_change(%{"read_mark" => "nonsense"})
    assert User.ui_setting(Accounts.get_user!(user.id), "read_mark") == "stamp"
  end

  test "the Personal tab saves the profile and shows validation errors", %{conn: conn, user: user} do
    {:ok, _} = Accounts.create_user(%{email: "taken@example.com", username: "taken", password: "password1234"})
    {:ok, view, _html} = live(conn, ~p"/settings/personal")

    html = view |> form("#profile-form", profile: %{username: "taken"}) |> render_submit()
    assert html =~ "has already been taken"

    html = view |> form("#profile-form", profile: %{username: "sam", display_name: "Sam I Am"}) |> render_submit()
    assert html =~ "Profile saved."
    assert html =~ "Sam I Am"
    assert Accounts.get_user!(user.id).display_name == "Sam I Am"
  end

  test "changing the password keeps this session and drops the old tokens", %{conn: conn, access: access} do
    conn =
      post(conn, ~p"/settings/password", %{
        "current_password" => "password1234",
        "password" => "a-new-password",
        "password_confirmation" => "a-new-password"
      })

    assert redirected_to(conn) == "/settings/security"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password changed"
    assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
    assert {:ok, _} = TokenHelper.resource_from_token(get_session(conn, "guardian_default_token"))
    assert {:ok, _} = Accounts.authenticate_user("sam", "a-new-password")

    # The renewed session still opens the settings page.
    assert {:ok, _view, _html} = conn |> recycle() |> live(~p"/settings/security")
  end

  test "a wrong current password changes nothing", %{conn: conn, access: access} do
    conn =
      post(conn, ~p"/settings/password", %{
        "current_password" => "nope",
        "password" => "a-new-password",
        "password_confirmation" => "a-new-password"
      })

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "current password"
    assert {:ok, _} = TokenHelper.resource_from_token(access)
    assert {:ok, _} = Accounts.authenticate_user("sam", "password1234")
  end

  test "the email changes only with the current password", %{conn: conn, user: user} do
    conn1 = post(conn, ~p"/settings/email", %{"current_password" => "nope", "email" => "new@example.com"})
    assert Phoenix.Flash.get(conn1.assigns.flash, :error) =~ "current password"
    assert Accounts.get_user!(user.id).email == "sam@example.com"

    conn2 = post(conn, ~p"/settings/email", %{"current_password" => "password1234", "email" => "new@example.com"})
    assert Phoenix.Flash.get(conn2.assigns.flash, :info) =~ "new@example.com"
    assert Accounts.get_user!(user.id).email == "new@example.com"
  end

  test "signing out everywhere keeps this session", %{conn: conn, access: access} do
    conn = post(conn, ~p"/settings/sessions/revoke", %{})

    assert redirected_to(conn) == "/settings/security"
    assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
    assert {:ok, _} = TokenHelper.resource_from_token(get_session(conn, "guardian_default_token"))
  end
end
