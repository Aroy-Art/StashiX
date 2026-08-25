defmodule StashixWeb.AdminLive do
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Library}

  on_mount {StashixWeb.Live.Hooks, :require_admin}

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users()
    libraries = Library.list_libraries(%{role: :admin})

    {:ok,
     assign(socket,
       page_title: "Admin",
       users: users,
       libraries: libraries,
       tab: "users",
       user_form: to_form(%{"email" => "", "username" => "", "password" => "", "role" => "user"}),
       library_form: to_form(%{"name" => "", "root_path" => ""}),
       errors: %{},
       show_user_form: false,
       show_library_form: false
     )}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("toggle_user_form", _params, socket) do
    {:noreply, update(socket, :show_user_form, &(!&1))}
  end

  def handle_event("toggle_library_form", _params, socket) do
    {:noreply, update(socket, :show_library_form, &(!&1))}
  end

  def handle_event(
        "create_user",
        %{"email" => email, "username" => username, "password" => password, "role" => role},
        socket
      ) do
    case Accounts.create_user(%{email: email, username: username, password: password, role: String.to_atom(role)}) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:users, Accounts.list_users())
         |> assign(:show_user_form, false)
         |> put_flash(:info, "User created")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("delete_user", %{"id" => id}, socket) do
    if id == socket.assigns.current_user.id do
      {:noreply, put_flash(socket, :error, "Cannot delete yourself")}
    else
      user = Accounts.get_user!(id)
      Accounts.delete_user(user)
      {:noreply, assign(socket, :users, Accounts.list_users())}
    end
  end

  def handle_event(
        "create_library",
        %{"name" => name, "root_path" => root_path},
        socket
      ) do
    case Library.create_library(%{name: name, root_path: root_path}) do
      {:ok, _lib} ->
        {:noreply,
         socket
         |> assign(:libraries, Library.list_libraries(%{role: :admin}))
         |> assign(:show_library_form, false)
         |> put_flash(:info, "Library created")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("scan_library", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id)
    {:noreply, put_flash(socket, :info, "Scan started")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-white">Admin Panel</h1>

      <div class="flex gap-2 border-b border-gray-800 pb-0">
        <%= for {label, tab} <- [{"Users", "users"}, {"Libraries", "libraries"}] do %>
          <button
            phx-click="set_tab"
            phx-value-tab={tab}
            class={[
              "px-4 py-2 text-sm font-medium -mb-px border-b-2 transition-colors",
              if(@tab == tab,
                do: "border-indigo-500 text-indigo-400",
                else: "border-transparent text-gray-500 hover:text-gray-300"
              )
            ]}
          >
            {label}
          </button>
        <% end %>
      </div>

      <%= if @tab == "users" do %>
        <div class="space-y-4">
          <div class="flex justify-end">
            <button
              phx-click="toggle_user_form"
              class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
            >
              Add User
            </button>
          </div>

          <%= if @show_user_form do %>
            <div class="bg-gray-900 border border-gray-700 rounded-xl p-6">
              <h3 class="text-white font-medium mb-4">Create User</h3>
              <form phx-submit="create_user" class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Email</label>
                  <input type="email" name="email" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Username</label>
                  <input type="text" name="username" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Password</label>
                  <input type="password" name="password" required minlength="8" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500" />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Role</label>
                  <select name="role" class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500">
                    <option value="user">User</option>
                    <option value="admin">Admin</option>
                  </select>
                </div>
                <div class="col-span-2 flex gap-2 justify-end">
                  <button type="button" phx-click="toggle_user_form" class="px-3 py-1.5 text-sm text-gray-400 hover:text-white">Cancel</button>
                  <button type="submit" class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg">Create</button>
                </div>
              </form>
            </div>
          <% end %>

          <div class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-gray-800">
                  <th class="text-left px-4 py-3 text-gray-400 font-medium">Username</th>
                  <th class="text-left px-4 py-3 text-gray-400 font-medium">Email</th>
                  <th class="text-left px-4 py-3 text-gray-400 font-medium">Role</th>
                  <th class="px-4 py-3"></th>
                </tr>
              </thead>
              <tbody>
                <%= for user <- @users do %>
                  <tr class="border-b border-gray-800 last:border-0">
                    <td class="px-4 py-3 text-white">{user.username}</td>
                    <td class="px-4 py-3 text-gray-400">{user.email}</td>
                    <td class="px-4 py-3">
                      <span class={[
                        "px-2 py-0.5 rounded text-xs font-medium",
                        if(user.role == :admin, do: "bg-indigo-900 text-indigo-300", else: "bg-gray-800 text-gray-400")
                      ]}>
                        {user.role}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <%= if user.id != @current_user.id do %>
                        <button
                          phx-click="delete_user"
                          phx-value-id={user.id}
                          data-confirm="Delete this user?"
                          class="text-red-500 hover:text-red-400 text-xs"
                        >
                          Delete
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <%= if @tab == "libraries" do %>
        <div class="space-y-4">
          <div class="flex justify-end">
            <button
              phx-click="toggle_library_form"
              class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
            >
              Add Library
            </button>
          </div>

          <%= if @show_library_form do %>
            <div class="bg-gray-900 border border-gray-700 rounded-xl p-6">
              <h3 class="text-white font-medium mb-4">Create Library</h3>
              <form phx-submit="create_library" class="space-y-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Name</label>
                  <input type="text" name="name" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500" placeholder="My Comics" />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Root Path</label>
                  <input type="text" name="root_path" required class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500" placeholder="/libraries/comics" />
                </div>
                <div class="flex gap-2 justify-end">
                  <button type="button" phx-click="toggle_library_form" class="px-3 py-1.5 text-sm text-gray-400 hover:text-white">Cancel</button>
                  <button type="submit" class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg">Create</button>
                </div>
              </form>
            </div>
          <% end %>

          <div class="space-y-3">
            <%= for lib <- @libraries do %>
              <div class="bg-gray-900 border border-gray-800 rounded-xl p-4 flex items-center justify-between">
                <div>
                  <p class="text-white font-medium">{lib.name}</p>
                  <p class="text-gray-500 text-sm">{lib.root_path}</p>
                </div>
                <button
                  phx-click="scan_library"
                  phx-value-id={lib.id}
                  class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm rounded-lg border border-gray-700"
                >
                  Scan
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
