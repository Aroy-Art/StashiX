defmodule StashixWeb.Live.Hooks do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Stashix.Auth.TokenHelper
  alias Stashix.Library

  def on_mount(:require_auth, _params, session, socket) do
    case authenticate_from_session(session) do
      {:ok, user} ->
        libraries = Library.list_libraries(user)

        initial_progress =
          if connected?(socket) do
            Enum.each(libraries, &Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{&1.id}"))
            load_active_scan_progress(libraries)
          else
            %{}
          end

        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: libraries, sidebar_scan_progress: initial_progress)
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

        initial_progress =
          if connected?(socket) do
            Enum.each(libraries, &Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{&1.id}"))
            load_active_scan_progress(libraries)
          else
            %{}
          end

        socket =
          socket
          |> assign(current_user: user, sidebar_libraries: libraries, sidebar_scan_progress: initial_progress)
          |> attach_hook(:sidebar_scan, :handle_event, &handle_sidebar_scan/3)
          |> attach_hook(:sidebar_scan_progress, :handle_info, &handle_sidebar_progress/2)

        {:cont, socket}

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

  defp handle_sidebar_scan("sidebar_scan", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id)
    {:halt, put_flash(socket, :info, "Scan started")}
  end

  defp handle_sidebar_scan("sidebar_force_scan", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id, true)
    {:halt, put_flash(socket, :info, "Force scan started")}
  end

  defp handle_sidebar_scan(_event, _params, socket), do: {:cont, socket}

  defp handle_sidebar_progress({:scan_progress, %{library_id: id, scanned: s, total: t, done: done, phase: phase}}, socket) do
    socket = update(socket, :sidebar_scan_progress, &Map.put(&1, id, %{scanned: s, total: t, done: done, phase: phase}))
    if done, do: Process.send_after(self(), {:clear_sidebar_scan_progress, id}, 3_000)
    {:cont, socket}
  end

  defp handle_sidebar_progress({:scan_progress, %{library_id: id, scanned: s, total: t, done: done}}, socket) do
    socket = update(socket, :sidebar_scan_progress, &Map.put(&1, id, %{scanned: s, total: t, done: done, phase: :scan}))
    if done, do: Process.send_after(self(), {:clear_sidebar_scan_progress, id}, 3_000)
    {:cont, socket}
  end

  defp handle_sidebar_progress({:clear_sidebar_scan_progress, id}, socket) do
    {:halt, update(socket, :sidebar_scan_progress, &Map.delete(&1, id))}
  end

  defp handle_sidebar_progress(_msg, socket), do: {:cont, socket}

  defp load_active_scan_progress(libraries) do
    library_ids = MapSet.new(libraries, & &1.id)

    Stashix.Scanner.list_active_tasks()
    |> Enum.filter(&(not &1.done and MapSet.member?(library_ids, &1.library_id)))
    |> Map.new(fn task ->
      {task.library_id, %{scanned: task.scanned, total: task.total, done: task.done, phase: Map.get(task, :phase, :scan)}}
    end)
  end

  defp authenticate_from_session(session) do
    access_token = session["guardian_default_token"]

    case access_token && TokenHelper.resource_from_token(access_token) do
      {:ok, user} ->
        {:ok, user}

      _ ->
        refresh_token = session["guardian_refresh_token"]

        case refresh_token && TokenHelper.refresh_tokens(refresh_token) do
          {:ok, user, _new_access, _new_refresh} -> {:ok, user}
          _ -> {:error, :unauthenticated}
        end
    end
  end
end
