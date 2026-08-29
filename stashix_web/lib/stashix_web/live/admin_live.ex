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
       show_library_form: false,
       editing_library_id: nil,
       deleted_books: [],
       deleted_series: [],
       selected_books: MapSet.new(),
       selected_series: MapSet.new(),
       pending_confirm: nil,
       scanning_libraries: MapSet.new()
     )}
  end

  @impl true
  def handle_params(%{"tab" => tab}, _uri, socket) when tab in ~w(users libraries cleanup) do
    socket =
      case tab do
        "cleanup" ->
          socket
          |> assign(:deleted_books, Library.list_all_deleted_books())
          |> assign(:deleted_series, Library.list_all_deleted_series())
          |> assign(:selected_books, MapSet.new())
          |> assign(:selected_series, MapSet.new())

        _ ->
          socket
      end

    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?tab=#{tab}")}
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
    {:noreply, update(socket, :scanning_libraries, &MapSet.put(&1, id))}
  end

  def handle_event("force_scan_library", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id, true)
    {:noreply, update(socket, :scanning_libraries, &MapSet.put(&1, id))}
  end

  def handle_event("edit_library", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_library_id, id)}
  end

  def handle_event("cancel_edit_library", _params, socket) do
    {:noreply, assign(socket, :editing_library_id, nil)}
  end

  def handle_event("save_standalone_folders", %{"_id" => id, "standalone_folders" => raw}, socket) do
    library = Library.get_library!(id)
    folders = raw |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    case Library.update_library(library, %{standalone_folders: folders}) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:libraries, Library.list_libraries(%{role: :admin}))
         |> assign(:editing_library_id, nil)
         |> put_flash(:info, "Library settings saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save")}
    end
  end

  def handle_event("show_confirm", params, socket) do
    confirm = %{
      title: params["title"],
      message: params["message"],
      confirm_label: params["label"] || "Confirm",
      event: params["event"],
      event_params: Map.take(params, ["ids", "id"])
    }

    {:noreply, assign(socket, :pending_confirm, confirm)}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :pending_confirm, nil)}
  end

  def handle_event("confirm_action", _params, socket) do
    %{event: event, event_params: params} = socket.assigns.pending_confirm
    socket = assign(socket, :pending_confirm, nil)
    handle_event(event, params, socket)
  end

  def handle_event("toggle_book", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_books, id),
        do: MapSet.delete(socket.assigns.selected_books, id),
        else: MapSet.put(socket.assigns.selected_books, id)

    {:noreply, assign(socket, :selected_books, selected)}
  end

  def handle_event("toggle_series", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_series, id),
        do: MapSet.delete(socket.assigns.selected_series, id),
        else: MapSet.put(socket.assigns.selected_series, id)

    {:noreply, assign(socket, :selected_series, selected)}
  end

  def handle_event("select_all_books", _params, socket) do
    all_ids = Enum.map(socket.assigns.deleted_books, & &1.id) |> MapSet.new()
    selected = if socket.assigns.selected_books == all_ids, do: MapSet.new(), else: all_ids
    {:noreply, assign(socket, :selected_books, selected)}
  end

  def handle_event("select_all_series", _params, socket) do
    all_ids = Enum.map(socket.assigns.deleted_series, & &1.id) |> MapSet.new()
    selected = if socket.assigns.selected_series == all_ids, do: MapSet.new(), else: all_ids
    {:noreply, assign(socket, :selected_series, selected)}
  end

  def handle_event("batch_restore_books", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_books)
    Library.batch_restore_books(ids)

    {:noreply,
     socket
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> assign(:selected_books, MapSet.new())
     |> put_flash(:info, "#{length(ids)} book(s) restored")}
  end

  def handle_event("batch_purge_books", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_books)
    Library.batch_purge_books(ids)

    {:noreply,
     socket
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> assign(:selected_books, MapSet.new())
     |> put_flash(:info, "#{length(ids)} book(s) permanently deleted")}
  end

  def handle_event("batch_restore_series", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_series)
    Library.batch_restore_series(ids)

    {:noreply,
     socket
     |> assign(:deleted_series, Library.list_all_deleted_series())
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> assign(:selected_series, MapSet.new())
     |> assign(:selected_books, MapSet.new())
     |> put_flash(:info, "#{length(ids)} series restored")}
  end

  def handle_event("batch_purge_series", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_series)
    Library.batch_purge_series(ids)

    {:noreply,
     socket
     |> assign(:deleted_series, Library.list_all_deleted_series())
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> assign(:selected_series, MapSet.new())
     |> assign(:selected_books, MapSet.new())
     |> put_flash(:info, "#{length(ids)} series permanently deleted")}
  end

  def handle_event("purge_book", %{"id" => id}, socket) do
    book = Library.get_book!(id)
    Library.purge_book(book)

    {:noreply,
     socket
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> put_flash(:info, "Book permanently deleted")}
  end

  def handle_event("purge_series", %{"id" => id}, socket) do
    series = Library.get_series!(id)
    Library.purge_series(series)

    {:noreply,
     socket
     |> assign(:deleted_series, Library.list_all_deleted_series())
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> put_flash(:info, "Series permanently deleted")}
  end

  def handle_event("restore_book", %{"id" => id}, socket) do
    book = Library.get_book!(id)
    Library.restore_book(book)

    {:noreply,
     socket
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> put_flash(:info, "Book restored")}
  end

  def handle_event("restore_series", %{"id" => id}, socket) do
    series = Library.get_series!(id)
    Library.restore_series(series)

    {:noreply,
     socket
     |> assign(:deleted_series, Library.list_all_deleted_series())
     |> assign(:deleted_books, Library.list_all_deleted_books())
     |> put_flash(:info, "Series and its books restored")}
  end

  @impl true
  def handle_info({:scan_progress, %{library_id: id, done: true}}, socket) do
    {:noreply, update(socket, :scanning_libraries, &MapSet.delete(&1, id))}
  end

  def handle_info({:scan_progress, %{library_id: id, scanned: s, total: t}}, socket) do
    {:noreply, update(socket, :scanning_libraries, fn libs ->
      if t > 0 and s < t, do: MapSet.put(libs, id), else: libs
    end)}
  end

  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.confirm_dialog confirm={@pending_confirm} />
    <div class="space-y-6">
      <h1 class="text-2xl font-bold text-white">Admin Panel</h1>

      <div class="flex gap-2 border-b border-gray-800 pb-0">
        <%= for {label, tab} <- [{"Users", "users"}, {"Libraries", "libraries"}, {"Cleanup", "cleanup"}] do %>
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
                          phx-click="show_confirm"
                          phx-value-event="delete_user"
                          phx-value-id={user.id}
                          phx-value-title="Delete User"
                          phx-value-message={"Delete user \"#{user.username}\"? This cannot be undone."}
                          phx-value-label="Delete"
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
              <div class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
                <div class="p-4 flex items-center justify-between">
                  <div>
                    <p class="text-white font-medium">{lib.name}</p>
                    <p class="text-gray-500 text-sm">{lib.root_path}</p>
                    <%= if lib.standalone_folders != [] do %>
                      <p class="text-xs text-gray-600 mt-1">
                        Standalone folders: {Enum.join(lib.standalone_folders, ", ")}
                      </p>
                    <% end %>
                  </div>
                  <%
                    scanning = MapSet.member?(@scanning_libraries, lib.id)
                  %>
                  <div class="flex gap-2 items-center">
                    <button
                      phx-click="edit_library"
                      phx-value-id={lib.id}
                      class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm rounded-lg border border-gray-700"
                    >
                      Settings
                    </button>
                    <button
                      phx-click="scan_library"
                      phx-value-id={lib.id}
                      disabled={scanning}
                      class={["px-3 py-1.5 text-sm rounded-lg border flex items-center gap-1.5",
                        if(scanning,
                          do: "bg-gray-900 text-gray-500 border-gray-800 cursor-not-allowed",
                          else: "bg-gray-800 hover:bg-gray-700 text-gray-300 border-gray-700"
                        )]}
                    >
                      <%= if scanning do %>
                        <.icon name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" />
                        Scanning...
                      <% else %>
                        Scan
                      <% end %>
                    </button>
                    <button
                      phx-click="force_scan_library"
                      phx-value-id={lib.id}
                      disabled={scanning}
                      class={["px-3 py-1.5 text-sm rounded-lg border",
                        if(scanning,
                          do: "bg-gray-900 text-gray-600 border-gray-800 cursor-not-allowed",
                          else: "bg-gray-800 hover:bg-gray-700 text-amber-400 border-gray-700"
                        )]}
                    >
                      Force Rescan
                    </button>
                  </div>
                </div>

                <%= if @editing_library_id == lib.id do %>
                  <div class="border-t border-gray-800 p-4 bg-gray-950">
                    <form phx-submit="save_standalone_folders" class="space-y-3">
                      <input type="hidden" name="_id" value={lib.id} />
                      <div>
                        <label class="block text-xs font-medium text-gray-400 mb-1">
                          Standalone folder names
                          <span class="text-gray-600 font-normal ml-1">(one per line — case insensitive)</span>
                        </label>
                        <textarea
                          name="standalone_folders"
                          rows="4"
                          class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-white text-sm font-mono focus:outline-none focus:border-violet-500"
                          placeholder={"Default built-in: one-shot, one shot, oneshot\nAdd extras here, e.g.:\nAnnuals\nSpecials"}
                        >{Enum.join(lib.standalone_folders, "\n")}</textarea>
                        <p class="text-xs text-gray-600 mt-1">
                          Built-in defaults (always active): <span class="text-gray-500">one-shot, one shot, oneshot</span>
                        </p>
                      </div>
                      <div class="flex gap-2 justify-end">
                        <button type="button" phx-click="cancel_edit_library" class="px-3 py-1.5 text-sm text-gray-400 hover:text-white">Cancel</button>
                        <button type="submit" class="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-sm rounded-lg">Save</button>
                      </div>
                    </form>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @tab == "cleanup" do %>
        <%
          all_series_ids = Enum.map(@deleted_series, & &1.id) |> MapSet.new()
          all_books_ids = Enum.map(@deleted_books, & &1.id) |> MapSet.new()
          all_series_selected = @deleted_series != [] and @selected_series == all_series_ids
          all_books_selected = @deleted_books != [] and @selected_books == all_books_ids
          series_sel_count = MapSet.size(@selected_series)
          books_sel_count = MapSet.size(@selected_books)
        %>
        <div class="space-y-8">
          <%!-- Series section --%>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-white">
                Deleted Series
                <span class="ml-2 text-sm font-normal text-gray-500">({length(@deleted_series)})</span>
              </h2>
              <%= if series_sel_count > 0 do %>
                <div class="flex items-center gap-3">
                  <span class="text-sm text-gray-400">{series_sel_count} selected</span>
                  <button
                    phx-click="batch_restore_series"
                    class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
                  >
                    Restore Selected
                  </button>
                  <button
                    phx-click="show_confirm"
                    phx-value-event="batch_purge_series"
                    phx-value-title="Purge Series"
                    phx-value-message={"Permanently delete #{series_sel_count} series and ALL their books? This cannot be undone."}
                    phx-value-label="Purge"
                    class="px-3 py-1.5 bg-red-700 hover:bg-red-600 text-white text-sm rounded-lg"
                  >
                    Purge Selected
                  </button>
                </div>
              <% end %>
            </div>
            <%= if @deleted_series == [] do %>
              <p class="text-gray-500 text-sm">No deleted series.</p>
            <% else %>
              <div class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="border-b border-gray-800">
                      <th class="px-4 py-3 w-8">
                        <input
                          type="checkbox"
                          phx-click="select_all_series"
                          checked={all_series_selected}
                          class="rounded border-gray-600 bg-gray-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                        />
                      </th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Series</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Library</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Deleted</th>
                      <th class="px-4 py-3"></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for s <- @deleted_series do %>
                      <tr class={[
                        "border-b border-gray-800 last:border-0 transition-colors",
                        if(MapSet.member?(@selected_series, s.id), do: "bg-indigo-950/30", else: "")
                      ]}>
                        <td class="px-4 py-3">
                          <input
                            type="checkbox"
                            phx-click="toggle_series"
                            phx-value-id={s.id}
                            checked={MapSet.member?(@selected_series, s.id)}
                            class="rounded border-gray-600 bg-gray-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                          />
                        </td>
                        <td class="px-4 py-3 text-white">{s.name}</td>
                        <td class="px-4 py-3 text-gray-400">{s.library.name}</td>
                        <td class="px-4 py-3 text-gray-500 text-xs">{Calendar.strftime(s.deleted_at, "%Y-%m-%d %H:%M")}</td>
                        <td class="px-4 py-3 text-right flex gap-3 justify-end">
                          <button
                            phx-click="restore_series"
                            phx-value-id={s.id}
                            class="text-indigo-400 hover:text-indigo-300 text-xs"
                          >
                            Restore
                          </button>
                          <button
                            phx-click="show_confirm"
                            phx-value-event="purge_series"
                            phx-value-id={s.id}
                            phx-value-title="Purge Series"
                            phx-value-message={"Permanently delete \"#{s.name}\" and all its books? This cannot be undone."}
                            phx-value-label="Purge"
                            class="text-red-500 hover:text-red-400 text-xs"
                          >
                            Purge
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>

          <%!-- Books section --%>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-white">
                Deleted Books
                <span class="ml-2 text-sm font-normal text-gray-500">({length(@deleted_books)})</span>
              </h2>
              <%= if books_sel_count > 0 do %>
                <div class="flex items-center gap-3">
                  <span class="text-sm text-gray-400">{books_sel_count} selected</span>
                  <button
                    phx-click="batch_restore_books"
                    class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
                  >
                    Restore Selected
                  </button>
                  <button
                    phx-click="show_confirm"
                    phx-value-event="batch_purge_books"
                    phx-value-title="Purge Books"
                    phx-value-message={"Permanently delete #{books_sel_count} book(s)? This cannot be undone."}
                    phx-value-label="Purge"
                    class="px-3 py-1.5 bg-red-700 hover:bg-red-600 text-white text-sm rounded-lg"
                  >
                    Purge Selected
                  </button>
                </div>
              <% end %>
            </div>
            <%= if @deleted_books == [] do %>
              <p class="text-gray-500 text-sm">No deleted books.</p>
            <% else %>
              <div class="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="border-b border-gray-800">
                      <th class="px-4 py-3 w-8">
                        <input
                          type="checkbox"
                          phx-click="select_all_books"
                          checked={all_books_selected}
                          class="rounded border-gray-600 bg-gray-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                        />
                      </th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Title</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Series</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Library</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Path</th>
                      <th class="text-left px-4 py-3 text-gray-400 font-medium">Deleted</th>
                      <th class="px-4 py-3"></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for b <- @deleted_books do %>
                      <tr class={[
                        "border-b border-gray-800 last:border-0 transition-colors",
                        if(MapSet.member?(@selected_books, b.id), do: "bg-indigo-950/30", else: "")
                      ]}>
                        <td class="px-4 py-3">
                          <input
                            type="checkbox"
                            phx-click="toggle_book"
                            phx-value-id={b.id}
                            checked={MapSet.member?(@selected_books, b.id)}
                            class="rounded border-gray-600 bg-gray-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                          />
                        </td>
                        <td class="px-4 py-3 text-white">{b.title}</td>
                        <td class="px-4 py-3 text-gray-400">{if b.series, do: b.series.name, else: "—"}</td>
                        <td class="px-4 py-3 text-gray-400">{b.library.name}</td>
                        <td class="px-4 py-3 text-gray-600 text-xs font-mono truncate max-w-xs" title={b.path}>{b.path}</td>
                        <td class="px-4 py-3 text-gray-500 text-xs">{Calendar.strftime(b.deleted_at, "%Y-%m-%d %H:%M")}</td>
                        <td class="px-4 py-3 text-right flex gap-3 justify-end">
                          <button
                            phx-click="restore_book"
                            phx-value-id={b.id}
                            class="text-indigo-400 hover:text-indigo-300 text-xs"
                          >
                            Restore
                          </button>
                          <button
                            phx-click="show_confirm"
                            phx-value-event="purge_book"
                            phx-value-id={b.id}
                            phx-value-title="Purge Book"
                            phx-value-message={"Permanently delete \"#{b.title}\"? This cannot be undone."}
                            phx-value-label="Purge"
                            class="text-red-500 hover:text-red-400 text-xs"
                          >
                            Purge
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
