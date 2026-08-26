defmodule StashixWeb.Live.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Stashix.Auth.TokenHelper
  alias Stashix.Library

  def on_mount(:require_auth, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        libraries = Library.list_libraries(user)

        if connected?(socket) do
          Enum.each(libraries, &Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{&1.id}"))
        end

        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: libraries, sidebar_scan_progress: %{})
          |> attach_hook(:sidebar_scan, :handle_event, &handle_sidebar_scan/3)
          |> attach_hook(:sidebar_scan_progress, :handle_info, &handle_sidebar_progress/2)

        {:cont, socket}

      {:error, _} ->
        {:halt, redirect(socket, to: "/login")}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} when user.role == :admin ->
        libraries = Library.list_libraries(user)

        if connected?(socket) do
          Enum.each(libraries, &Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{&1.id}"))
        end

        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: libraries, sidebar_scan_progress: %{})
          |> attach_hook(:sidebar_scan, :handle_event, &handle_sidebar_scan/3)
          |> attach_hook(:sidebar_scan_progress, :handle_info, &handle_sidebar_progress/2)

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

  defp handle_sidebar_progress({:scan_progress, %{library_id: id, scanned: s, total: t, done: done}}, socket) do
    socket = update(socket, :sidebar_scan_progress, &Map.put(&1, id, %{scanned: s, total: t, done: done}))
    if done, do: Process.send_after(self(), {:clear_sidebar_scan_progress, id}, 3_000)
    {:cont, socket}
  end

  defp handle_sidebar_progress({:scan_progress, %{library_id: id, scanned: s, total: t}}, socket) do
    {:cont, update(socket, :sidebar_scan_progress, &Map.put(&1, id, %{scanned: s, total: t, done: false}))}
  end

  defp handle_sidebar_progress({:clear_sidebar_scan_progress, id}, socket) do
    {:halt, update(socket, :sidebar_scan_progress, &Map.delete(&1, id))}
  end

  defp handle_sidebar_progress(_msg, socket), do: {:cont, socket}

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
