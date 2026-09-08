defmodule StashixWeb.UserController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias StashixWeb.Schemas

  operation :profile,
    summary: "Get current user profile",
    tags: ["Users"],
    security: [%{"Bearer" => []}],
    responses: [
      ok: {"User profile", "application/json", Schemas.User},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def profile(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    json(conn, %{
      id: user.id,
      email: user.email,
      username: user.username,
      role: user.role,
      birth_date: user.birth_date
    })
  end
end
