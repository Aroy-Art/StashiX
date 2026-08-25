defmodule StashixWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Stashix.Auth.TokenHelper

  def init(opts), do: opts

  def call(conn, _opts) do
    token = get_session(conn, :guardian_default_token)

    case token && TokenHelper.resource_from_token(token) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      _ ->
        conn
        |> redirect(to: "/login")
        |> halt()
    end
  end
end
