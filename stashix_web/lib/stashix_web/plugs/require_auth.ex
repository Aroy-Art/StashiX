defmodule StashixWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias Stashix.Auth.TokenHelper

  def init(opts), do: opts

  def call(conn, _opts) do
    access_token = get_session(conn, :guardian_default_token)

    case access_token && TokenHelper.resource_from_token(access_token) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      _ ->
        refresh_token = get_session(conn, :guardian_refresh_token)

        case refresh_token && TokenHelper.refresh_tokens(refresh_token) do
          {:ok, user, new_access, new_refresh} ->
            conn
            |> put_session("guardian_default_token", new_access)
            |> put_session("guardian_refresh_token", new_refresh)
            |> assign(:current_user, user)

          _ ->
            conn
            |> redirect(to: "/login")
            |> halt()
        end
    end
  end
end
