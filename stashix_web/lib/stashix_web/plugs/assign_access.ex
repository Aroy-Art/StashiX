defmodule StashixWeb.Plugs.AssignAccess do
  @moduledoc "Assigns `:access` (a `Stashix.Library.Access`) for the authenticated user."
  import Plug.Conn

  alias Stashix.Library.Access

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)
    assign(conn, :access, Access.for_user(user))
  end
end
