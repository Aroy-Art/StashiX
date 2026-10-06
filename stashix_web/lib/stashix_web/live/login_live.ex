defmodule StashixWeb.LoginLive do
  use StashixWeb, :live_view

  import StashixWeb.AuthComponents

  alias Stashix.Accounts

  on_mount {StashixWeb.Live.Hooks, :optional_auth}

  @impl true
  def mount(_params, session, socket) do
    token = session["guardian_default_token"]

    already_authed =
      token && match?({:ok, _}, Stashix.Auth.TokenHelper.resource_from_token(token))

    if already_authed do
      {:ok, redirect(socket, to: "/")}
    else
      {:ok,
       assign(socket,
         page_title: "Login",
         form: to_form(%{"login" => "", "password" => ""}),
         error: nil,
         trigger_submit: false
       ), layout: false}
    end
  end

  @impl true
  def handle_event("login", %{"login" => login, "password" => password}, socket) do
    case Accounts.authenticate_user(login, password) do
      {:ok, _user} ->
        {:noreply,
         assign(socket,
           trigger_submit: true,
           form: to_form(%{"login" => login, "password" => password})
         )}

      {:error, :rate_limited} ->
        {:noreply, assign(socket, error: "Too many failed attempts. Try again in a few minutes.")}

      {:error, _} ->
        {:noreply, assign(socket, error: "Invalid email/username or password")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.cover_page heading="Sign in" issue="#1">
      <p
        :if={@error}
        role="alert"
        class="mb-4 px-3 py-2 border-l-4 border-red-500 bg-red-500/10 text-sm font-medium text-red-200"
      >
        {@error}
      </p>

      <form
        id="login-form"
        method="post"
        action={~p"/login"}
        phx-submit="login"
        phx-trigger-action={@trigger_submit}
        class="space-y-4"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <.field label="Email or username">
          <.text_input
            name="login"
            value={@form["login"].value}
            required
            autofocus
            autocomplete="username"
            placeholder="you@example.com"
          />
        </.field>
        <.field label="Password">
          <.text_input type="password" name="password" required autocomplete="current-password" />
        </.field>
        <.ink_button type="submit" class="w-full mt-2">
          <.icon name="lucide-book-open" class="w-4 h-4" /> Open the box
        </.ink_button>
      </form>
    </.cover_page>
    """
  end
end
