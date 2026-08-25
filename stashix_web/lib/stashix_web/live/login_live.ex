defmodule StashixWeb.LoginLive do
  use StashixWeb, :live_view

  alias Stashix.Accounts

  on_mount {StashixWeb.Live.Hooks, :optional_auth}

  @impl true
  def mount(_params, session, socket) do
    if session["guardian_default_token"] do
      {:ok, redirect(socket, to: "/")}
    else
      {:ok,
       assign(socket,
         page_title: "Login",
         form: to_form(%{"email" => "", "password" => ""}),
         error: nil,
         trigger_submit: false
       )}
    end
  end

  @impl true
  def handle_event("login", %{"email" => email, "password" => password}, socket) do
    case Accounts.authenticate_user(email, password) do
      {:ok, _user} ->
        {:noreply, assign(socket, trigger_submit: true, form: to_form(%{"email" => email, "password" => password}))}

      {:error, _} ->
        {:noreply, assign(socket, error: "Invalid email or password")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 flex items-center justify-center">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-white">Stashix</h1>
          <p class="text-gray-400 mt-2">Sign in to your library</p>
        </div>

        <div class="bg-gray-900 rounded-xl border border-gray-800 p-8">
          <%= if @error do %>
            <div class="mb-4 p-3 bg-red-900/50 border border-red-700 rounded-lg text-red-300 text-sm">
              {@error}
            </div>
          <% end %>

          <form
            id="login-form"
            method="post"
            action={~p"/login"}
            phx-submit="login"
            phx-trigger-action={@trigger_submit}
            class="space-y-4"
          >
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Email</label>
              <input
                type="email"
                name="email"
                value={@form["email"].value}
                required
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500"
                placeholder="you@example.com"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Password</label>
              <input
                type="password"
                name="password"
                required
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500"
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              class="w-full bg-indigo-600 hover:bg-indigo-500 text-white font-medium py-2 px-4 rounded-lg transition-colors"
            >
              Sign In
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
