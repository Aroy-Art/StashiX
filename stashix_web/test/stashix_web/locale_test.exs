# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.LocaleTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.Accounts
  alias Stashix.Accounts.User
  alias Stashix.Auth.TokenHelper
  alias StashixWeb.Locale

  @known ~w(en de pt_BR)

  describe "best_match/2" do
    test "takes the highest quality range the app knows" do
      assert Locale.best_match(["fr;q=0.9, de;q=0.8, en;q=0.5"], @known) == "de"
      assert Locale.best_match(["en;q=0.2, de"], @known) == "de"
    end

    test "matches regions exactly, then by language" do
      assert Locale.best_match(["pt-BR"], @known) == "pt_BR"
      assert Locale.best_match(["de-AT"], @known) == "de"
      assert Locale.best_match(["pt"], @known) == "pt_BR"
    end

    test "skips refused, wildcard and unknown ranges" do
      assert Locale.best_match(["de;q=0, en"], @known) == "en"
      assert Locale.best_match(["*"], @known) == nil
      assert Locale.best_match(["fr, ja"], @known) == nil
      assert Locale.best_match([], @known) == nil
    end
  end

  describe "resolve/3" do
    test "an account choice wins over the browser" do
      assert Locale.resolve("de", ["en"], @known) == "de"
    end

    test "auto follows the browser, then the default" do
      assert Locale.resolve("auto", ["de"], @known) == "de"
      assert Locale.resolve("auto", ["fr"], @known) == "en"
    end
  end

  describe "requests" do
    setup %{conn: conn} do
      {:ok, user} = Accounts.create_user(%{email: "lin@example.com", username: "lin", password: "password1234"})
      {:ok, access, refresh} = TokenHelper.generate_tokens(user)

      conn =
        Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

      %{conn: conn, user: user}
    end

    test "the page carries the resolved locale in lang and the session", %{conn: conn} do
      conn = conn |> put_req_header("accept-language", "en-GB,en;q=0.8") |> get(~p"/settings")
      assert html_response(conn, 200) =~ ~s(<html lang="en")
      assert get_session(conn, "locale") == "en"
    end

    test "Settings saves the language and reloads the page", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/settings")
      assert html =~ "ui-settings-locale"

      assert {:error, {:redirect, %{to: "/settings"}}} =
               view |> element("#ui-settings-locale") |> render_change(%{"locale" => "en"})

      assert User.locale(Accounts.get_user!(user.id)) == "en"
    end

    test "Settings rejects a language the app does not have", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/settings")
      assert view |> element("#ui-settings-locale") |> render_change(%{"locale" => "xx"}) =~ "not one of the choices"
      assert User.locale(Accounts.get_user!(user.id)) == "auto"
    end
  end
end
