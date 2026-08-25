defmodule StashixWeb.AuthController do
  use StashixWeb, :controller

  alias Stashix.Accounts
  alias Stashix.Auth.{TokenHelper, Guardian}

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        case TokenHelper.generate_tokens(user) do
          {:ok, access_token, refresh_token} ->
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
    end
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    with {:ok, claims} <- TokenHelper.verify_refresh_token(refresh_token),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         {:ok, access_token, new_refresh_token} <- TokenHelper.generate_tokens(user) do
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

  defp user_json(user) do
    %{
      id: user.id,
      email: user.email,
      username: user.username,
      role: user.role
    }
  end
end
