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
         step: :account,
         account_data: %{},
         account_errors: %{},
         library_errors: %{},
         trigger_submit: false,
         account_form: to_form(%{"email" => "", "username" => "", "password" => "", "password_confirmation" => ""}),
         library_form: to_form(%{"library_name" => "", "library_path" => ""})
       ), layout: {StashixWeb.Layouts, :root}}
    end
  end

  @impl true
  def handle_event("next", %{"email" => email, "username" => username, "password" => password, "password_confirmation" => confirmation} = params, socket) do
    errors =
      %{}
      |> then(fn e -> if email == "", do: Map.put(e, :email, ["can't be blank"]), else: e end)
      |> then(fn e -> if username == "", do: Map.put(e, :username, ["can't be blank"]), else: e end)
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
    <div class="min-h-screen bg-gray-950 flex items-center justify-center">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold text-white">Welcome to Stashix</h1>
          <p class="text-gray-400 mt-2">
            {if @step == :account, do: "Create your admin account", else: "Add your first library"}
          </p>
        </div>

        <div class="flex items-center justify-center gap-3 mb-8">
          <div class="flex items-center gap-2">
            <div class={[
              "w-7 h-7 rounded-full flex items-center justify-center text-sm font-medium",
              if(@step == :account, do: "bg-indigo-600 text-white", else: "bg-indigo-900 text-indigo-300")
            ]}>
              1
            </div>
            <span class={["text-sm", if(@step == :account, do: "text-white", else: "text-gray-400")]}>
              Account
            </span>
          </div>
          <div class="w-8 h-px bg-gray-700"></div>
          <div class="flex items-center gap-2">
            <div class={[
              "w-7 h-7 rounded-full flex items-center justify-center text-sm font-medium",
              if(@step == :library, do: "bg-indigo-600 text-white", else: "bg-gray-800 text-gray-500")
            ]}>
              2
            </div>
            <span class={["text-sm", if(@step == :library, do: "text-white", else: "text-gray-500")]}>
              Library
            </span>
          </div>
        </div>

        <div class="bg-gray-900 rounded-xl border border-gray-800 p-8">
          <%= if @step == :account do %>
            <form phx-submit="next" class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Email</label>
                <input
                  type="email"
                  name="email"
                  value={@account_form[:email].value}
                  required
                  autofocus
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
                />
                <%= if @account_errors[:email] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@account_errors[:email])}</p>
                <% end %>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Username</label>
                <input
                  type="text"
                  name="username"
                  value={@account_form[:username].value}
                  required
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
                />
                <%= if @account_errors[:username] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@account_errors[:username])}</p>
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
                <%= if @account_errors[:password] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@account_errors[:password])}</p>
                <% end %>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Confirm password</label>
                <input
                  type="password"
                  name="password_confirmation"
                  required
                  minlength="8"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
                />
                <%= if @account_errors[:password_confirmation] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@account_errors[:password_confirmation])}</p>
                <% end %>
              </div>

              <button
                type="submit"
                class="w-full bg-indigo-600 hover:bg-indigo-500 text-white font-medium py-2 px-4 rounded-lg transition-colors"
              >
                Continue
              </button>
            </form>
          <% else %>
            <form
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

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Library name</label>
                <input
                  type="text"
                  name="library_name"
                  value={@library_form[:library_name].value}
                  required
                  autofocus
                  placeholder="My Comics"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
                />
                <%= if @library_errors[:library_name] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@library_errors[:library_name])}</p>
                <% end %>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-1">Library path</label>
                <input
                  type="text"
                  name="library_path"
                  value={@library_form[:library_path].value}
                  required
                  placeholder="/mnt/comics"
                  class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white focus:outline-none focus:border-indigo-500"
                />
                <p class="text-gray-500 text-xs mt-1">Absolute path to the folder containing your books</p>
                <%= if @library_errors[:library_path] do %>
                  <p class="text-red-400 text-xs mt-1">{List.first(@library_errors[:library_path])}</p>
                <% end %>
              </div>

              <div class="flex gap-3 pt-1">
                <button
                  type="button"
                  phx-click="back"
                  class="flex-1 bg-gray-800 hover:bg-gray-700 text-gray-300 font-medium py-2 px-4 rounded-lg transition-colors"
                >
                  Back
                </button>
                <button
                  type="submit"
                  class="flex-2 flex-grow bg-indigo-600 hover:bg-indigo-500 text-white font-medium py-2 px-4 rounded-lg transition-colors"
                >
                  Finish Setup
                </button>
              </div>
            </form>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
