defmodule StashixWeb.TaskController do
  use StashixWeb, :controller

  def index(conn, _params) do
    tasks = Stashix.Scanner.list_active_tasks()
    json(conn, %{tasks: tasks})
  end
end
