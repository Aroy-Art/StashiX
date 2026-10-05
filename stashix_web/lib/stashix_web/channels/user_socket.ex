defmodule StashixWeb.UserSocket do
  use Phoenix.Socket

  alias Stashix.Auth.TokenHelper

  channel "library:*", StashixWeb.LibraryChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case TokenHelper.resource_from_token(token) do
      {:ok, user} -> {:ok, assign(socket, :user_id, user.id)}
      {:error, _} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
