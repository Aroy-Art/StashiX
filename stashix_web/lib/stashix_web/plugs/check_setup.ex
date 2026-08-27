defmodule StashixWeb.Plugs.CheckSetup do
  import Plug.Conn
  import Phoenix.Controller

  alias Stashix.Accounts

  def init(opts), do: opts

  def call(%{request_path: "/setup"} = conn, _opts) do
    if Accounts.setup_complete?() do
      conn |> redirect(to: "/login") |> halt()
    else
      conn
    end
  end

  def call(conn, _opts) do
    if Accounts.setup_complete?() do
      conn
    else
      conn |> redirect(to: "/setup") |> halt()
    end
  end
end
