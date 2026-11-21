# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Plugs.KoboAuth do
  @moduledoc """
  Sign-in for a Kobo: the store address set on the device is
  `/kobo/<app password>/`, so every request carries it. Assigns
  `:current_user` and `:app_password` (what the device's sync is kept
  under).
  """
  import Plug.Conn

  alias Stashix.Accounts

  def init(opts), do: opts

  def call(%{path_params: %{"token" => token}} = conn, _opts) do
    case Accounts.app_password_from_token(token) do
      %{user: user} = app_password -> conn |> assign(:current_user, user) |> assign(:app_password, app_password)
      nil -> unauthorized(conn)
    end
  end

  def call(conn, _opts), do: unauthorized(conn)

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
    |> halt()
  end
end
