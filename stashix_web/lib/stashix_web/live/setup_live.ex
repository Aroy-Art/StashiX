defmodule StashixWeb.SetupLive do
  use StashixWeb, :live_view

  alias Stashix.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.setup_complete?() do
      {:ok, redirect(socket, to: "/login")}
    else
      {:ok,
       assign(socket,
         page_title: "Setup",
         errors: %{},
         trigger_submit: false,
         form: to_form(%{"email" => "", "username" => "", "password" => ""})
       )}
    end
  end

  @impl true
  def handle_event("setup", params, socket) do
    {:noreply, assign(socket, trigger_submit: true, form: to_form(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950 flex items-center justify-center">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-white">Welcome to Stashix</h1>
          <p class="text-gray-400 mt-2">Create your admin account to get started</p>
        </div>

        <div class="bg-gray-900 rounded-xl border border-gray-800 p-8">
          <form
          id="setup-form"
          method="post"
          action={~p"/setup"}
          phx-submit="setup"
          phx-trigger-action={@trigger_submit}
          class="space-y-4"
        >
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Email</label>
              <input
                type="email"
                name="email"
                required
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
              />
              <%= if @errors[:email] do %>
                <p class="text-red-400 text-xs mt-1">{List.first(@errors[:email])}</p>
              <% end %>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Username</label>
              <input
                type="text"
                name="username"
                required
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
              />
              <%= if @errors[:username] do %>
                <p class="text-red-400 text-xs mt-1">{List.first(@errors[:username])}</p>
              <% end %>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-300 mb-1">Password</label>
              <input
                type="password"
                name="password"
                required
                minlength="8"
                class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
              />
              <%= if @errors[:password] do %>
                <p class="text-red-400 text-xs mt-1">{List.first(@errors[:password])}</p>
              <% end %>
            </div>

            <button
              type="submit"
              class="w-full bg-indigo-600 hover:bg-indigo-500 text-white font-medium py-2 px-4 rounded-lg transition-colors"
            >
              Create Admin Account
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
