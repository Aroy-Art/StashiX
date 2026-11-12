# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SetupLive do
  use StashixWeb, :live_view

  import StashixWeb.AuthComponents

  alias Stashix.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.setup_complete?() do
      {:ok, redirect(socket, to: "/login")}
    else
      {:ok,
       assign(socket,
         page_title: gettext("Setup"),
         step: :account,
         account_data: %{},
         account_errors: %{},
         library_errors: %{},
         trigger_submit: false,
         confirm_skip: false,
         skip_library: false,
         account_form:
           to_form(%{
             "email" => "",
             "username" => "",
             "password" => "",
             "password_confirmation" => ""
           }),
         library_form: to_form(%{"library_name" => "", "library_path" => ""})
       ), layout: false}
    end
  end

  @impl true
  def handle_event(
        "next",
        %{
          "email" => email,
          "username" => username,
          "password" => password,
          "password_confirmation" => confirmation
        } = params,
        socket
      ) do
    errors =
      %{}
      |> then(fn e -> if email == "", do: Map.put(e, :email, [dgettext("errors", "can't be blank")]), else: e end)
      |> then(fn e ->
        if username == "", do: Map.put(e, :username, [dgettext("errors", "can't be blank")]), else: e
      end)
      |> then(fn e ->
        if String.length(password) < 8,
          do: Map.put(e, :password, [dgettext("errors", "must be at least 8 characters")]),
          else: e
      end)
      |> then(fn e ->
        if password != confirmation,
          do: Map.put(e, :password_confirmation, [dgettext("errors", "passwords do not match")]),
          else: e
      end)

    if map_size(errors) == 0 do
      {:noreply,
       assign(socket,
         step: :library,
         account_data: %{"email" => email, "username" => username, "password" => password},
         account_errors: %{},
         account_form: to_form(params)
       )}
    else
      {:noreply, assign(socket, account_errors: errors, account_form: to_form(params))}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: :account, library_errors: %{})}
  end

  def handle_event("submit", params, socket) do
    {:noreply, assign(socket, trigger_submit: true, library_form: to_form(params))}
  end

  def handle_event("confirm_skip", _params, socket) do
    {:noreply, assign(socket, confirm_skip: true)}
  end

  def handle_event("cancel_skip", _params, socket) do
    {:noreply, assign(socket, confirm_skip: false)}
  end

  def handle_event("skip", _params, socket) do
    {:noreply, assign(socket, confirm_skip: false, skip_library: true, trigger_submit: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.cover_page
      issue="#0"
      tagline={gettext("First issue: set up your stash")}
      heading={if @step == :account, do: gettext("Create the admin account"), else: gettext("Add your first library")}
    >
      <:steps>
        <.cover_step number={1} current={@step == :account} done={@step == :library}>{gettext("Account")}</.cover_step>
        <span class="w-6 h-px bg-fg/20"></span>
        <.cover_step number={2} current={@step == :library}>{gettext("Library")}</.cover_step>
      </:steps>

      <form :if={@step == :account} phx-submit="next" class="space-y-4">
        <.field label={gettext("Email")} error={first_error(@account_errors, :email)}>
          <.text_input type="email" name="email" value={@account_form[:email].value} required autofocus />
        </.field>
        <.field label={gettext("Username")} error={first_error(@account_errors, :username)}>
          <.text_input name="username" value={@account_form[:username].value} required autocomplete="username" />
        </.field>
        <.field
          label={gettext("Password")}
          hint={gettext("At least 8 characters.")}
          error={first_error(@account_errors, :password)}
        >
          <.text_input type="password" name="password" required minlength="8" autocomplete="new-password" />
        </.field>
        <.field label={gettext("Confirm password")} error={first_error(@account_errors, :password_confirmation)}>
          <.text_input
            type="password"
            name="password_confirmation"
            required
            minlength="8"
            autocomplete="new-password"
          />
        </.field>
        <.ink_button type="submit" class="w-full mt-2">
          {gettext("Continue")} <.icon name="lucide-arrow-right" class="w-4 h-4" />
        </.ink_button>
      </form>

      <form
        :if={@step == :library}
        id="setup-form"
        method="post"
        action={~p"/setup"}
        phx-submit="submit"
        phx-trigger-action={@trigger_submit}
        class="space-y-4"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="email" value={@account_data["email"]} />
        <input type="hidden" name="username" value={@account_data["username"]} />
        <input type="hidden" name="password" value={@account_data["password"]} />
        <input :if={@skip_library} type="hidden" name="skip_library" value="true" />

        <.field label={gettext("Library name")} error={first_error(@library_errors, :library_name)}>
          <.text_input
            name="library_name"
            value={@library_form[:library_name].value}
            required
            autofocus
            placeholder={gettext("My Comics")}
          />
        </.field>
        <.field
          label={gettext("Library path")}
          hint={gettext("Absolute path to the folder containing your books.")}
          error={first_error(@library_errors, :library_path)}
        >
          <.text_input
            name="library_path"
            value={@library_form[:library_path].value}
            required
            mono
            placeholder="/mnt/comics"
          />
        </.field>
        <div class="flex gap-3 pt-2">
          <.ink_button type="button" variant="ghost" phx-click="back">{gettext("Back")}</.ink_button>
          <.ink_button type="submit" class="flex-1">{gettext("Finish setup")}</.ink_button>
        </div>
        <button
          type="button"
          phx-click="confirm_skip"
          class="block w-full text-center text-sm text-muted hover:text-fg underline underline-offset-4"
        >
          {gettext("Skip for now")}
        </button>
      </form>

      <.dialog
        :if={@confirm_skip}
        id="skip-library-dialog"
        size="sm"
        title={gettext("Skip library setup?")}
        on_close={JS.push("cancel_skip")}
      >
        <p class="text-sm text-fg-soft">
          {gettext("Your stash will start empty. You can add a library later under Admin → Libraries.")}
        </p>
        <.dialog_footer>
          <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_skip">{gettext("Cancel")}</.ink_button>
          <.ink_button type="button" size="md" phx-click="skip">{gettext("Skip and finish")}</.ink_button>
        </.dialog_footer>
      </.dialog>
    </.cover_page>
    """
  end

  defp first_error(errors, key) do
    case errors[key] do
      [message | _] -> message
      _ -> nil
    end
  end
end
