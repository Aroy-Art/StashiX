defmodule StashixWeb.UserController do
  use StashixWeb, :controller

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
