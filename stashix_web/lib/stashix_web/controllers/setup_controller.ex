defmodule StashixWeb.SetupController do
  use StashixWeb, :controller

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper

  def status(conn, _params) do
    json(conn, %{needs_setup: not Accounts.setup_complete?()})
  end

  def create(conn, %{"email" => email, "username" => username, "password" => password}) do
    if Accounts.setup_complete?() do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "setup already complete"})
    else
      case Accounts.create_user(%{
             email: email,
             username: username,
             password: password,
             role: :admin
           }) do
        {:ok, user} ->
          {:ok, access_token, refresh_token} = TokenHelper.generate_tokens(user)

          conn
          |> put_status(:created)
          |> json(%{
            access_token: access_token,
            refresh_token: refresh_token,
            user: %{
              id: user.id,
              email: user.email,
              username: user.username,
              role: user.role
            }
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
