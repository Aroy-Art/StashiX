defmodule StashixWeb.Live.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Stashix.Auth.TokenHelper
  alias Stashix.Library

  def on_mount(:require_auth, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: Library.list_libraries(user))
          |> attach_hook(:sidebar_scan, :handle_event, &handle_sidebar_scan/3)

        {:cont, socket}

      {:error, _} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} when user.role == :admin ->
        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: Library.list_libraries(user))
          |> attach_hook(:sidebar_scan, :handle_event, &handle_sidebar_scan/3)

        {:cont, socket}

      {:ok, _user} ->
        {:halt, redirect(socket, to: "/")}

      {:error, _} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  defp handle_sidebar_scan("sidebar_scan", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id)
    {:halt, put_flash(socket, :info, "Scan started")}
  end

  defp handle_sidebar_scan("sidebar_force_scan", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id, true)
    {:halt, put_flash(socket, :info, "Force scan started")}
  end

  defp handle_sidebar_scan(_event, _params, socket), do: {:cont, socket}

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
