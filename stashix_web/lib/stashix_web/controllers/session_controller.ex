defmodule StashixWeb.SessionController do
  use StashixWeb, :controller

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper

  def create(conn, params) do
    login = Map.get(params, "login") || Map.get(params, "email", "")
    password = Map.get(params, "password", "")

    case Accounts.authenticate_user(login, password) do
      {:ok, user} ->
        conn
        |> sign_in(user)
        |> redirect(to: ~p"/")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many failed attempts. Try again in a few minutes.")
        |> redirect(to: ~p"/login")

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
      %{
        "email" => email,
        "username" => username,
        "password" => password,
        "library_name" => library_name,
        "library_path" => library_path
      } = params

      with {:ok, user} <-
             Accounts.create_user(%{
               email: email,
               username: username,
               password: password,
               role: :admin
             }),
           {:ok, library} <-
             Stashix.Library.create_library(%{name: library_name, root_path: library_path}) do
        Stashix.Scanner.scan_library(library.id)

        conn
        |> sign_in(user)
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
    Accounts.delete_session(get_session(conn, "session_id"))

    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end

  @doc "Starts a recorded session for the user and writes it to the cookie."
  def sign_in(conn, user) do
    user_agent = conn |> get_req_header("user-agent") |> List.first()
    ip_address = conn.remote_ip && conn.remote_ip |> :inet.ntoa() |> List.to_string()
    {:ok, access_token, refresh_token, session_id} = TokenHelper.start_session(user, user_agent, ip_address)

    conn
    |> put_session("guardian_default_token", access_token)
    |> put_session("guardian_refresh_token", refresh_token)
    |> put_session("session_id", session_id)
    |> put_session(:live_socket_id, Accounts.session_topic(user.id))
  end
end
