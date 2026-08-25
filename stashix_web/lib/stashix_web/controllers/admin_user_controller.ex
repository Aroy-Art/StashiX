defmodule StashixWeb.AdminUserController do
  use StashixWeb, :controller

  alias Stashix.{Accounts, Library}

  def index(conn, _params) do
    users = Accounts.list_users()

    json(conn, %{
      users:
        Enum.map(users, fn u ->
          %{
            id: u.id,
            email: u.email,
            username: u.username,
            role: u.role,
            birth_date: u.birth_date,
            inserted_at: u.inserted_at
          }
        end)
    })
  end

  def create(conn, params) do
    case Accounts.create_user(params) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> json(%{user: %{id: user.id, email: user.email, username: user.username, role: user.role}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = Accounts.get_user!(id)

    case Accounts.update_user(user, params) do
      {:ok, updated} ->
        json(conn, %{user: %{id: updated.id, email: updated.email, username: updated.username, role: updated.role}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user) do
      {:ok, _} -> json(conn, %{status: "deleted"})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  def permissions(conn, %{"id" => id} = params) do
    attrs = %{
      user_id: id,
      library_id: params["library_id"],
      can_read: params["can_read"],
      max_age_rating: params["max_age_rating"]
    }

    case Library.set_library_permission(attrs) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, changeset} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
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
