defmodule StashixWeb.SessionController do
  use StashixWeb, :controller

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        {:ok, access_token, refresh_token} = TokenHelper.generate_tokens(user)

        conn
        |> put_session("guardian_default_token", access_token)
        |> put_session("guardian_refresh_token", refresh_token)
        |> redirect(to: ~p"/")

      {:error, _} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/login")
    end
  end

  def setup(conn, %{"email" => email, "username" => username, "password" => password}) do
    if Accounts.setup_complete?() do
      redirect(conn, to: ~p"/login")
    else
      case Accounts.create_user(%{email: email, username: username, password: password, role: :admin}) do
        {:ok, user} ->
          {:ok, access_token, refresh_token} = TokenHelper.generate_tokens(user)

          conn
          |> put_session("guardian_default_token", access_token)
          |> put_session("guardian_refresh_token", refresh_token)
          |> redirect(to: ~p"/")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Failed to create account. Check your details and try again.")
          |> redirect(to: ~p"/setup")
      end
    end
  end

  def delete(conn, _params) do
    conn
    |> delete_session("guardian_default_token")
    |> redirect(to: ~p"/login")
  end
end
