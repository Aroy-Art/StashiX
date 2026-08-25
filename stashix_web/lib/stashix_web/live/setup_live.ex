defmodule StashixWeb.SetupLive do
  use StashixWeb, :live_view

  alias Stashix.Accounts
  alias Stashix.Auth.TokenHelper

  @impl true
  def mount(_params, _session, socket) do
    if Accounts.setup_complete?() do
      {:ok, redirect(socket, to: "/login")}
    else
      {:ok,
       assign(socket,
         page_title: "Setup",
         error: nil,
         errors: %{}
       )}
    end
  end

  @impl true
  def handle_event(
        "setup",
        %{"email" => email, "username" => username, "password" => password},
        socket
      ) do
    case Accounts.create_user(%{
           email: email,
           username: username,
           password: password,
           role: :admin
         }) do
      {:ok, user} ->
        {:ok, access_token, _} = TokenHelper.generate_tokens(user)

        {:noreply,
         socket
         |> push_event("set_token", %{token: access_token})
         |> redirect(to: "/")}

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

        {:noreply, assign(socket, errors: errors)}
    end
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
          <form phx-submit="setup" class="space-y-4">
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
