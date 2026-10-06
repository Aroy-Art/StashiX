defmodule StashixWeb.SettingsController do
  @moduledoc """
  The account changes that touch credentials. They are plain form posts
  rather than LiveView events because each one ends by writing fresh tokens
  to the session cookie, which a LiveView cannot do: changing the password or
  signing out everywhere revokes every token, including this browser's.
  """
  use StashixWeb, :controller

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper
  alias StashixWeb.SessionController

  plug :require_user

  def update_password(conn, params) do
    attrs = Map.take(params, ["password", "password_confirmation"])

    case Accounts.change_password(conn.assigns.current_user, params["current_password"], attrs) do
      {:ok, user} ->
        conn
        |> renew_session(user)
        |> put_flash(:info, "Password changed. Other devices have been signed out.")
        |> back()

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> back()
    end
  end

  def update_email(conn, params) do
    case Accounts.change_email(conn.assigns.current_user, params["current_password"], Map.take(params, ["email"])) do
      {:ok, user} ->
        conn |> put_flash(:info, "Email changed to #{user.email}.") |> back()

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> back()
    end
  end

  def revoke_sessions(conn, _params) do
    {:ok, user} = Accounts.revoke_sessions(conn.assigns.current_user)

    conn
    |> renew_session(user)
    |> put_flash(:info, "Signed out everywhere else.")
    |> back()
  end

  defp back(conn), do: redirect(conn, to: ~p"/settings/security")

  # Fresh tokens for this browser, since the old ones were just revoked.
  defp renew_session(conn, user) do
    conn
    |> configure_session(renew: true)
    |> SessionController.sign_in(user)
  end

  defp error_message(:invalid_password), do: "The current password is not right."
  defp error_message(:rate_limited), do: "Too many wrong attempts. Try again in a few minutes."

  defp error_message(%Ecto.Changeset{} = changeset) do
    {field, {message, opts}} = hd(changeset.errors)

    message =
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
      end)

    "#{field |> to_string() |> String.replace("_", " ") |> String.capitalize()} #{message}."
  end

  defp require_user(conn, _opts) do
    case TokenHelper.user_from_session(get_session(conn)) do
      {:ok, user} -> assign(conn, :current_user, user)
      {:error, _} -> conn |> redirect(to: ~p"/login") |> halt()
    end
  end
end
