defmodule StashixWeb.AuthController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Accounts
  alias Stashix.Auth.{TokenHelper, Guardian}
  alias StashixWeb.Schemas

  operation :login,
    summary: "Authenticate user",
    tags: ["Auth"],
    request_body: {"Login credentials", "application/json", Schemas.LoginRequest, required: true},
    responses: [
      ok: {"Auth tokens and user", "application/json", Schemas.AuthResponse},
      unauthorized: {"Invalid credentials", "application/json", Schemas.Error},
      too_many_requests: {"Too many failed attempts", "application/json", Schemas.Error}
    ]

  def login(conn, params) do
    login = Map.get(params, "login") || Map.get(params, "email", "")
    password = Map.get(params, "password", "")

    case Accounts.authenticate_user(login, password) do
      {:ok, user} ->
        case TokenHelper.start_session(user, conn |> get_req_header("user-agent") |> List.first(), ip_string(conn)) do
          {:ok, access_token, refresh_token, _session_id} ->
            json(conn, %{
              access_token: access_token,
              refresh_token: refresh_token,
              user: user_json(user)
            })

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "token generation failed: #{inspect(reason)}"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid credentials"})

      {:error, :invalid_password} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid credentials"})

      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "too many failed attempts, try again later"})
    end
  end

  operation :refresh,
    summary: "Refresh access token",
    tags: ["Auth"],
    request_body: {"Refresh token", "application/json", Schemas.RefreshRequest, required: true},
    responses: [
      ok: {"New auth tokens", "application/json", Schemas.AuthResponse},
      unauthorized: {"Invalid token", "application/json", Schemas.Error}
    ]

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    with {:ok, claims} <- TokenHelper.verify_refresh_token(refresh_token),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         {:ok, access_token, new_refresh_token} <- TokenHelper.generate_tokens(user, claims["sid"]) do
      Accounts.touch_session(claims["sid"], extend: true)

      json(conn, %{
        access_token: access_token,
        refresh_token: new_refresh_token,
        user: user_json(user)
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid refresh token: #{inspect(reason)}"})
    end
  end

  defp ip_string(conn) do
    case conn.remote_ip do
      nil -> nil
      ip -> ip |> :inet.ntoa() |> List.to_string()
    end
  end

  defp user_json(user) do
    %{
      id: user.id,
      email: user.email,
      username: user.username,
      display_name: user.display_name,
      role: user.role
    }
  end
end
