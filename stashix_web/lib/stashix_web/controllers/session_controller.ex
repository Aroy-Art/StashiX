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

  def setup(conn, params) do
    if Accounts.setup_complete?() do
      redirect(conn, to: ~p"/login")
    else
      %{"email" => email, "username" => username, "password" => password,
        "library_name" => library_name, "library_path" => library_path} = params

      with {:ok, user} <-
             Accounts.create_user(%{email: email, username: username, password: password, role: :admin}),
           {:ok, library} <-
             Stashix.Library.create_library(%{name: library_name, root_path: library_path}) do
        Stashix.Scanner.scan_library(library.id)
        {:ok, access_token, refresh_token} = TokenHelper.generate_tokens(user)

        conn
        |> put_session("guardian_default_token", access_token)
        |> put_session("guardian_refresh_token", refresh_token)
        |> redirect(to: ~p"/")
      else
        {:error, _} ->
          conn
          |> put_flash(:error, "Setup failed. Check your details and try again.")
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
