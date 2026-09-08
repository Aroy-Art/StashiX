defmodule StashixWeb.AdminUserController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.{Accounts, Library}
  alias StashixWeb.Schemas

  operation :index,
    summary: "List all users (admin)",
    tags: ["Admin"],
    security: [%{"Bearer" => []}],
    responses: [
      ok:
        {"User list", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{users: %OpenApiSpex.Schema{type: :array, items: Schemas.User}}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def index(conn, _params) do
    users = Accounts.list_users()

    json(conn, %{
      users:
        Enum.map(users, fn u ->
          %{
            id: u.id,
            email: u.email,
            username: u.username,
            display_name: u.display_name,
            role: u.role,
            birth_date: u.birth_date,
            inserted_at: u.inserted_at
          }
        end)
    })
  end

  operation :create,
    summary: "Create user (admin)",
    tags: ["Admin"],
    security: [%{"Bearer" => []}],
    request_body: {"User params", "application/json", Schemas.SetupRequest, required: true},
    responses: [
      created:
        {"Created user", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{user: Schemas.User}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def create(conn, params) do
    case Accounts.create_user(params) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> json(%{
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

  operation :update,
    summary: "Update user (admin)",
    tags: ["Admin"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body:
      {"User params", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           email: %OpenApiSpex.Schema{type: :string},
           username: %OpenApiSpex.Schema{type: :string},
           password: %OpenApiSpex.Schema{type: :string},
           role: %OpenApiSpex.Schema{type: :string, enum: ["admin", "user"]}
         }
       }, required: true},
    responses: [
      ok: {"Updated user", "application/json", %OpenApiSpex.Schema{type: :object, properties: %{user: Schemas.User}}},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def update(conn, %{"id" => id} = params) do
    user = Accounts.get_user!(id)

    case Accounts.update_user(user, params) do
      {:ok, updated} ->
        json(conn, %{
          user: %{
            id: updated.id,
            email: updated.email,
            username: updated.username,
            display_name: updated.display_name,
            role: updated.role
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  operation :delete,
    summary: "Delete user (admin)",
    tags: ["Admin"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok:
        {"Deleted", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{status: %OpenApiSpex.Schema{type: :string}}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def delete(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user) do
      {:ok, _} ->
        json(conn, %{status: "deleted"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  operation :permissions,
    summary: "Set user library permissions (admin)",
    tags: ["Admin"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body: {"Permissions", "application/json", Schemas.PermissionsRequest, required: true},
    responses: [
      ok:
        {"Permissions set", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{status: %OpenApiSpex.Schema{type: :string}}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def permissions(conn, %{"id" => id} = params) do
    attrs = %{
      user_id: id,
      library_id: params["library_id"],
      can_read: params["can_read"],
      max_age_rating: params["max_age_rating"]
    }

    case Library.set_library_permission(attrs) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
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
