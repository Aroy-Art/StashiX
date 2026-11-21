# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Plugs.KoreaderAuth do
  @moduledoc """
  Sign-in for KOReader's progress sync: the `x-auth-user` header (user name
  or email) and `x-auth-key` (the MD5 of one of the user's app passwords;
  see `Stashix.Accounts.authenticate_koreader/2`). Assigns `:current_user`.
  """
  import Plug.Conn

  alias Stashix.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with [login] <- get_req_header(conn, "x-auth-user"),
         [key] <- get_req_header(conn, "x-auth-key"),
         %Accounts.User{} = user <- Accounts.authenticate_koreader(login, key) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{code: 2001, message: "Unauthorized"}))
        |> halt()
    end
  end
end
