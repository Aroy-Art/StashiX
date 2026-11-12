# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

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
        |> put_flash(:info, gettext("Password changed. Other devices have been signed out."))
        |> back()

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> back()
    end
  end

  def update_email(conn, params) do
    case Accounts.change_email(conn.assigns.current_user, params["current_password"], Map.take(params, ["email"])) do
      {:ok, user} ->
        conn |> put_flash(:info, gettext("Email changed to %{email}.", email: user.email)) |> back()

      {:error, reason} ->
        conn |> put_flash(:error, error_message(reason)) |> back()
    end
  end

  def revoke_sessions(conn, _params) do
    {:ok, user} = Accounts.revoke_sessions(conn.assigns.current_user)

    conn
    |> renew_session(user)
    |> put_flash(:info, gettext("Signed out everywhere else."))
    |> back()
  end

  defp back(conn), do: redirect(conn, to: ~p"/settings/security")

  # Fresh tokens for this browser, since the old ones were just revoked.
  defp renew_session(conn, user) do
    conn
    |> configure_session(renew: true)
    |> SessionController.sign_in(user)
  end

  defp error_message(:invalid_password), do: gettext("The current password is not right.")
  defp error_message(:rate_limited), do: gettext("Too many wrong attempts. Try again in a few minutes.")

  defp error_message(%Ecto.Changeset{} = changeset) do
    {field, error} = hd(changeset.errors)

    gettext("%{field} %{message}.",
      field: field_label(field),
      message: StashixWeb.CoreComponents.translate_error(error)
    )
  end

  defp field_label(:email), do: gettext("Email")
  defp field_label(:password), do: gettext("Password")
  defp field_label(:password_confirmation), do: gettext("Password confirmation")
  defp field_label(field), do: field |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp require_user(conn, _opts) do
    case TokenHelper.user_from_session(get_session(conn)) do
      {:ok, user} -> assign(conn, :current_user, user)
      {:error, _} -> conn |> redirect(to: ~p"/login") |> halt()
    end
  end
end
