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

  describe "the sessions list" do
    @firefox "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
    @chrome_android "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Mobile Safari/537.36"

    defp sign_in(user_agent) do
      build_conn()
      |> put_req_header("user-agent", user_agent)
      |> post(~p"/login", %{"login" => "sam", "password" => "password1234"})
    end

    test "names each sign-in and marks the one being used", %{user: user} do
      conn = sign_in(@firefox)
      {:ok, _} = Accounts.create_session(user, @chrome_android)

      {:ok, view, _html} = conn |> recycle() |> live(~p"/settings/security")

      assert view |> element("#sessions li", "Firefox on Linux") |> render() =~ "This one"
      refute view |> element("#sessions li", "Chrome on Android") |> render() =~ "This one"
      refute has_element?(view, "#sessions-empty")
    end

    test "says so when nothing is recorded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/security")
      assert has_element?(view, "#sessions-empty")
    end

    test "signing out removes the session", %{user: user} do
      conn = sign_in(@firefox)
      assert [_] = Accounts.list_sessions(user)

      conn |> recycle() |> delete(~p"/logout")
      assert [] = Accounts.list_sessions(user)
    end

    test "a session can be signed out on its own, which ends its tokens", %{user: user} do
      conn = sign_in(@firefox)
      {:ok, access, refresh, other_id} = TokenHelper.start_session(user, @chrome_android)
      assert {:ok, _} = TokenHelper.resource_from_token(access)

      {:ok, view, _html} = conn |> recycle() |> live(~p"/settings/security")
      # This browser comes first and has no button of its own.
      refute has_element?(view, "#sessions li:first-child button")

      html = view |> element("#sessions button[phx-value-id='#{other_id}']") |> render_click()
      refute html =~ "Chrome on Android"
      assert html =~ "Firefox on Linux"

      assert {:error, :token_revoked} = TokenHelper.resource_from_token(access)
      assert {:error, :token_revoked} = TokenHelper.refresh_tokens(refresh)
      assert {:ok, _} = TokenHelper.resource_from_token(get_session(conn, "guardian_default_token"))
    end

    test "nobody signs out a session that is not theirs, nor the one in use", %{user: user} do
      {:ok, other} = Accounts.create_user(%{email: "pat@example.com", username: "pat", password: "password1234"})
      {:ok, theirs} = Accounts.create_session(other, @firefox)
      assert {:error, :not_found} = Accounts.revoke_session(user, theirs.id)
      assert {:error, :not_found} = Accounts.revoke_session(user, "nonsense")
      assert [_] = Accounts.list_sessions(other)

      conn = sign_in(@firefox)
      {:ok, view, _html} = conn |> recycle() |> live(~p"/settings/security")
      render_click(view, "revoke_session", %{"id" => get_session(conn, "session_id")})
      assert [_] = Accounts.list_sessions(user)
    end

    test "signing out everywhere else leaves only this browser", %{user: user} do
      conn = sign_in(@firefox)
      {:ok, _} = Accounts.create_session(user, @chrome_android)

      conn = conn |> recycle() |> put_req_header("user-agent", @firefox) |> post(~p"/settings/sessions/revoke", %{})

      assert [session] = Accounts.list_sessions(Accounts.get_user!(user.id))
      assert session.id == get_session(conn, "session_id")
    end
  end
end
