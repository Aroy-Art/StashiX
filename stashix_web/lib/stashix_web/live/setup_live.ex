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
         page_title: "Setup",
         step: :account,
         account_data: %{},
         account_errors: %{},
         library_errors: %{},
         trigger_submit: false,
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
      |> then(fn e -> if email == "", do: Map.put(e, :email, ["can't be blank"]), else: e end)
      |> then(fn e ->
        if username == "", do: Map.put(e, :username, ["can't be blank"]), else: e
      end)
      |> then(fn e ->
        if String.length(password) < 8,
          do: Map.put(e, :password, ["must be at least 8 characters"]),
          else: e
      end)
      |> then(fn e ->
        if password != confirmation,
          do: Map.put(e, :password_confirmation, ["passwords do not match"]),
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

  @impl true
  def render(assigns) do
    ~H"""
    <.cover_page
      issue="#0"
      tagline="First issue: set up your stash"
      heading={if @step == :account, do: "Create the admin account", else: "Add your first library"}
    >
      <:steps>
        <.cover_step number={1} current={@step == :account} done={@step == :library}>Account</.cover_step>
        <span class="w-6 h-px bg-white/20"></span>
        <.cover_step number={2} current={@step == :library}>Library</.cover_step>
      </:steps>

      <form :if={@step == :account} phx-submit="next" class="space-y-4">
        <.field label="Email" error={first_error(@account_errors, :email)}>
          <.text_input type="email" name="email" value={@account_form[:email].value} required autofocus />
        </.field>
        <.field label="Username" error={first_error(@account_errors, :username)}>
          <.text_input name="username" value={@account_form[:username].value} required autocomplete="username" />
        </.field>
        <.field label="Password" hint="At least 8 characters." error={first_error(@account_errors, :password)}>
          <.text_input type="password" name="password" required minlength="8" autocomplete="new-password" />
        </.field>
        <.field label="Confirm password" error={first_error(@account_errors, :password_confirmation)}>
          <.text_input
            type="password"
            name="password_confirmation"
            required
            minlength="8"
            autocomplete="new-password"
          />
        </.field>
        <.ink_button type="submit" class="w-full mt-2">
          Continue <.icon name="lucide-arrow-right" class="w-4 h-4" />
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

        <.field label="Library name" error={first_error(@library_errors, :library_name)}>
          <.text_input
            name="library_name"
            value={@library_form[:library_name].value}
            required
            autofocus
            placeholder="My Comics"
          />
        </.field>
        <.field
          label="Library path"
          hint="Absolute path to the folder containing your books."
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
          <.ink_button type="button" variant="ghost" phx-click="back">Back</.ink_button>
          <.ink_button type="submit" class="flex-1">Finish setup</.ink_button>
        </div>
      </form>
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
