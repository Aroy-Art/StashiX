# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Plugs.OpdsAuth do
  @moduledoc """
  HTTP Basic sign-in for OPDS clients: the user's name (or email) and one of
  their app passwords (`Stashix.Accounts.AppPassword`), never the account
  password. Assigns `:current_user`; anything else gets a 401 that asks for
  credentials.
  """
  import Plug.Conn

  alias Stashix.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {login, password} <- Plug.BasicAuth.parse_basic_auth(conn),
         %Accounts.User{} = user <- Accounts.authenticate_app_password(login, password) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", ~s(Basic realm="Stashix OPDS", charset="UTF-8"))
        |> unauthorized(conn.path_info)
        |> halt()
    end
  end

  # OPDS 2 clients read how to sign in from an authentication document.
  defp unauthorized(conn, ["opds", "v2" | _]) do
    conn
    |> put_resp_content_type("application/opds-authentication+json")
    |> send_resp(401, Jason.encode_to_iodata!(StashixWeb.Opds.Feed2.authentication_document()))
  end

  defp unauthorized(conn, _path) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Sign in with your user name and an app password from Settings.")
  end
end
