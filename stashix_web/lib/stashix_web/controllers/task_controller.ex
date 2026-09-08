defmodule StashixWeb.TaskController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias StashixWeb.Schemas

  operation :index,
    summary: "List active scan tasks",
    tags: ["Tasks"],
    security: [%{"Bearer" => []}],
    responses: [
      ok: {"Task list", "application/json", %OpenApiSpex.Schema{
        type: :object,
        properties: %{tasks: %OpenApiSpex.Schema{type: :array, items: Schemas.Task}}
      }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def index(conn, _params) do
    tasks = Stashix.Scanner.list_active_tasks()
    json(conn, %{tasks: tasks})
  end
end
