defmodule StashixWeb.SetupController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper
  alias StashixWeb.Schemas

  operation :status,
    summary: "Check if initial setup is needed",
    tags: ["Setup"],
    responses: [
      ok: {"Setup status", "application/json", Schemas.SetupStatusResponse}
    ]

  def status(conn, _params) do
    json(conn, %{needs_setup: not Accounts.setup_complete?()})
  end

  operation :create,
    summary: "Create initial admin account",
    tags: ["Setup"],
    request_body: {"Setup credentials", "application/json", Schemas.SetupRequest, required: true},
    responses: [
      created: {"Admin created with tokens", "application/json", Schemas.AuthResponse},
      forbidden: {"Setup already complete", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

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
              display_name: user.display_name,
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
