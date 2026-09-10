defmodule StashixWeb.Plugs.MediaAuth do
  import Plug.Conn

  alias Stashix.Auth.TokenHelper

  def init(opts), do: opts

  def call(conn, _opts) do
    session = get_session(conn)

    case authenticate(session) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      :error ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end

  defp authenticate(session) do
    access_token = session["guardian_default_token"]

    case access_token && TokenHelper.resource_from_token(access_token) do
      {:ok, user} ->
        {:ok, user}

      _ ->
        refresh_token = session["guardian_refresh_token"]

        case refresh_token && TokenHelper.refresh_tokens(refresh_token) do
          {:ok, user, _access, _refresh} -> {:ok, user}
          _ -> :error
        end
    end
  end
end
