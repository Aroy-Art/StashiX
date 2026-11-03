# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SetupLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.Accounts
  alias Stashix.Library.Library
  alias Stashix.Repo

  @account %{
    "email" => "admin@example.com",
    "username" => "admin",
    "password" => "password1234",
    "password_confirmation" => "password1234"
  }

  defp to_library_step(conn) do
    {:ok, view, _html} = live(conn, ~p"/setup")
    view |> form("form[phx-submit=next]", @account) |> render_submit()
    view
  end

  test "skipping the library asks first, then finishes setup without one", %{conn: conn} do
    view = to_library_step(conn)

    refute has_element?(view, "#skip-library-dialog")
    view |> element("button", "Skip for now") |> render_click()
    assert has_element?(view, "#skip-library-dialog")

    view |> element("#skip-library-dialog button", "Cancel") |> render_click()
    refute has_element?(view, "#skip-library-dialog")

    view |> element("button", "Skip for now") |> render_click()
    view |> element("#skip-library-dialog button", "Skip and finish") |> render_click()

    conn = follow_trigger_action(form(view, "#setup-form"), conn)

    assert redirected_to(conn) == "/"
    assert Accounts.setup_complete?()
    assert Repo.aggregate(Library, :count) == 0
  end

  test "a library that fails to save leaves no admin, so setup can be retried", %{conn: conn} do
    conn = post(conn, ~p"/setup", Map.merge(@account, %{"library_name" => "", "library_path" => ""}))

    assert redirected_to(conn) == "/setup"
    refute Accounts.setup_complete?()
    assert Repo.aggregate(Library, :count) == 0
  end
end
