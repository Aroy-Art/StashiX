defmodule StashixWeb.DialogHistory do
  @moduledoc """
  Keeps URL-driven dialogs (`?edit=true`, `?identify=…`) out of the way of the
  browser's back button.

  Opening a dialog pushes a history entry. Closing it pops that entry again
  instead of pushing another one, so "back" leaves the page rather than
  reopening the dialog, while "forward" still brings back a dialog that was
  dismissed by accident.
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView

  @doc """
  Call from `mount/3`. `params` are the query params that open a dialog.
  """
  def track_dialogs(socket, params) do
    socket
    |> assign(dialog_direct: nil, dialog_closing: false)
    |> attach_hook(:dialog_history, :handle_params, fn url_params, _uri, socket ->
      # Only a dialog that is open on the very first handle_params was reached
      # by loading its URL; every later one was opened by a patch and has the
      # dialog-less page right below it in the history.
      direct = is_nil(socket.assigns.dialog_direct) and Enum.any?(params, &Map.has_key?(url_params, &1))
      {:cont, assign(socket, dialog_direct: direct, dialog_closing: false)}
    end)
  end

  @doc """
  Closes the open dialog. `fallback` is the dialog-less path, used when there
  is no history entry of our own to go back to.
  """
  def close_dialog(%{assigns: %{dialog_closing: true}} = socket, _fallback), do: socket

  def close_dialog(%{assigns: %{dialog_direct: true}} = socket, fallback),
    do: push_patch(socket, to: fallback, replace: true)

  def close_dialog(socket, _fallback),
    do: socket |> assign(dialog_closing: true) |> push_event("history-back", %{})
end
