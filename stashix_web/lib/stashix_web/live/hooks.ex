defmodule StashixWeb.Live.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Stashix.Auth.TokenHelper

  def on_mount(:require_auth, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        {:cont, assign(socket, :current_user, user)}

      {:error, _} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} when user.role == :admin ->
        {:cont, assign(socket, :current_user, user)}

      {:ok, _user} ->
        {:halt, redirect(socket, to: "/")}

      {:error, _} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:optional_auth, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        {:cont, assign(socket, :current_user, user)}

      {:error, _} ->
        {:cont, assign(socket, :current_user, nil)}
    end
  end

  defp authenticate_from_session(session) do
    token = session["guardian_default_token"]

    if token do
      TokenHelper.resource_from_token(token)
    else
      {:error, :no_token}
    end
  end
end
