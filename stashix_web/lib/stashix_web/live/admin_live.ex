defmodule StashixWeb.AdminLive do
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Formatters, Library}

  on_mount {StashixWeb.Live.Hooks, :require_admin}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       admin_sidebar: true,
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
       scanning_libraries: MapSet.new(),
       publishers: [],
       all_publishers: [],
       publishers_with_aliases: [],
       alias_source_id: nil,
       alias_target_id: nil,
       alias_source_query: "",
       alias_target_query: "",
       alias_pending: false,
       publisher_tab: "aliases",
       pub_vis_search: "",
       pub_vis_page: 1,
       pub_vis_publishers: [],
       pub_vis_total: 0,
       pub_vis_stats: %{},
       users: [],
       libraries: [],
       selected_perm_user_id: nil,
       user_permissions: %{},
       saved_permissions: MapSet.new()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    push_navigate(socket, to: ~p"/admin/users")
  end

  defp apply_action(socket, :users, _params) do
    socket
    |> assign(:page_title, "Admin · Users")
    |> assign(:users, Accounts.list_users())
    |> assign(:libraries, Library.list_libraries(%{role: :admin}))
  end

  defp apply_action(socket, :libraries, _params) do
    socket
    |> assign(:page_title, "Admin · Libraries")
    |> assign(:libraries, Library.list_libraries(%{role: :admin}))
  end

  defp apply_action(socket, :cleanup, _params) do
    socket
    |> assign(:page_title, "Admin · Cleanup")
    |> assign(:deleted_books, Library.list_all_deleted_books())
    |> assign(:deleted_series, Library.list_all_deleted_series())
    |> assign(:selected_books, MapSet.new())
    |> assign(:selected_series, MapSet.new())
  end

  defp apply_action(socket, :publishers, params) do
    tab =
      if Map.get(params, "tab") in ["aliases", "visibility"], do: params["tab"], else: "aliases"

    socket
    |> assign(:page_title, "Admin · Publishers")
    |> assign(:publisher_tab, tab)
    |> assign(:publishers, Library.list_publishers())
    |> assign(:publishers_with_aliases, Library.list_publishers_with_aliases())
    |> load_vis_publishers()
  end

  defp load_vis_publishers(socket) do
    search = socket.assigns[:pub_vis_search] || ""
    page = socket.assigns[:pub_vis_page] || 1
    {pubs, total} = Library.list_all_publishers_admin(search: search, page: page, limit: 50)
    stats = Library.publisher_stats(Enum.map(pubs, & &1.id))

    socket
    |> assign(:pub_vis_publishers, pubs)
    |> assign(:pub_vis_total, total)
    |> assign(:pub_vis_stats, stats)
  end

  @impl true
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
    case Accounts.create_user(%{
           email: email,
           username: username,
           password: password,
           role: String.to_atom(role)
         }) do
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

  def handle_event("delete_library", %{"id" => id}, socket) do
    library = Library.get_library!(id)
    Library.delete_library(library)

    {:noreply,
     socket
     |> assign(:libraries, Library.list_libraries(%{role: :admin}))
     |> put_flash(:info, "Library \"#{library.name}\" and all its content deleted")}
  end

  def handle_event("scan_library", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id)
    {:noreply, update(socket, :scanning_libraries, &MapSet.put(&1, id))}
  end

  def handle_event("force_scan_library", %{"id" => id}, socket) do
    Stashix.Scanner.scan_library(id, true)
    {:noreply, update(socket, :scanning_libraries, &MapSet.put(&1, id))}
  end

  def handle_event("backfill_blurhashes", _params, socket) do
    Stashix.Scanner.backfill_blurhashes()

    {:noreply, put_flash(socket, :info, "Blurhash backfill started — check server logs for progress")}
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

  def handle_event("show_user_permissions", %{"id" => id}, socket) do
    if socket.assigns.selected_perm_user_id == id do
      {:noreply, assign(socket, selected_perm_user_id: nil, user_permissions: %{})}
    else
      permissions = Library.list_user_permissions(id)
      {:noreply, assign(socket, selected_perm_user_id: id, user_permissions: permissions)}
    end
  end

  def handle_event(
        "set_permission",
        %{"user_id" => user_id, "library_id" => library_id} = params,
        socket
      ) do
    can_read = Map.get(params, "can_read") == "true"
    max_age_rating = Map.get(params, "max_age_rating", "unknown")

    attrs = %{
      user_id: user_id,
      library_id: library_id,
      can_read: can_read,
      max_age_rating: max_age_rating
    }

    case Library.set_library_permission(attrs) do
      {:ok, _} ->
        permissions = Library.list_user_permissions(user_id)
        key = "#{user_id}-#{library_id}"
        Process.send_after(self(), {:clear_saved_perm, key}, 3000)

        {:noreply,
         socket
         |> assign(:user_permissions, permissions)
         |> update(:saved_permissions, &MapSet.put(&1, key))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update permission")}
    end
  end

  def handle_event("pub_vis_search", params, socket) do
    q = Map.get(params, "q") || Map.get(params, "value", "")

    {:noreply,
     socket
     |> assign(:pub_vis_search, q)
     |> assign(:pub_vis_page, 1)
     |> load_vis_publishers()}
  end

  def handle_event("pub_vis_page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:pub_vis_page, String.to_integer(page))
     |> load_vis_publishers()}
  end

  def handle_event("set_alias_source", %{"id" => id}, socket) do
    {:noreply, assign(socket, alias_source_id: id, alias_source_query: "", alias_pending: false)}
  end

  def handle_event("set_alias_target", %{"id" => id}, socket) do
    {:noreply, assign(socket, alias_target_id: id, alias_target_query: "", alias_pending: false)}
  end

  def handle_event("clear_alias_source", _params, socket) do
    {:noreply, assign(socket, alias_source_id: nil, alias_source_query: "", alias_pending: false)}
  end

  def handle_event("clear_alias_target", _params, socket) do
    {:noreply, assign(socket, alias_target_id: nil, alias_target_query: "", alias_pending: false)}
  end

  def handle_event("alias_source_input", %{"key" => "Enter", "value" => q}, socket) do
    result =
      socket.assigns.publishers
      |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(q)))
      |> List.first()

    case result do
      nil ->
        {:noreply, socket}

      pub ->
        {:noreply, assign(socket, alias_source_id: pub.id, alias_source_query: "", alias_pending: false)}
    end
  end

  def handle_event("alias_source_input", %{"value" => q}, socket) do
    {:noreply, assign(socket, alias_source_query: q, alias_source_id: nil)}
  end

  def handle_event("alias_target_input", %{"key" => "Enter", "value" => q}, socket) do
    result =
      socket.assigns.publishers
      |> Enum.reject(&(&1.id == socket.assigns.alias_source_id))
      |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(q)))
      |> List.first()

    case result do
      nil ->
        {:noreply, socket}

      pub ->
        {:noreply, assign(socket, alias_target_id: pub.id, alias_target_query: "", alias_pending: false)}
    end
  end

  def handle_event("alias_target_input", %{"value" => q}, socket) do
    {:noreply, assign(socket, alias_target_query: q, alias_target_id: nil)}
  end

  def handle_event("preview_alias", _params, socket) do
    {:noreply, assign(socket, :alias_pending, true)}
  end

  def handle_event("cancel_alias", _params, socket) do
    {:noreply, assign(socket, alias_pending: false)}
  end

  def handle_event("confirm_set_alias", _params, socket) do
    %{alias_source_id: alias_id, alias_target_id: master_id} = socket.assigns
    alias_pub = Enum.find(socket.assigns.publishers, &(&1.id == alias_id))
    master_pub = Enum.find(socket.assigns.publishers, &(&1.id == master_id))

    case Library.set_publisher_alias(alias_id, master_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(
           publishers: Library.list_publishers(),
           publishers_with_aliases: Library.list_publishers_with_aliases(),
           alias_source_id: nil,
           alias_target_id: nil,
           alias_pending: false
         )
         |> put_flash(:info, "\"#{alias_pub.name}\" is now an alias for \"#{master_pub.name}\"")}

      {:error, :same_publisher} ->
        {:noreply, put_flash(socket, :error, "A publisher cannot alias itself")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to set alias")}
    end
  end

  def handle_event("toggle_publisher_hidden", %{"id" => id}, socket) do
    case Library.toggle_publisher_hidden(id) do
      {:ok, pub} ->
        publishers = Library.list_publishers()

        {:noreply,
         socket
         |> assign(publishers: publishers)
         |> load_vis_publishers()
         |> put_flash(
           :info,
           if(pub.hidden, do: "\"#{pub.name}\" hidden", else: "\"#{pub.name}\" visible")
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update publisher")}
    end
  end

  def handle_event("remove_alias", %{"id" => id}, socket) do
    pub = Enum.find(socket.assigns.publishers_with_aliases, &(&1.id == id))

    case Library.remove_publisher_alias(id) do
      {:ok, _} ->
        publishers = Library.list_publishers()
        publishers_with_aliases = Library.list_publishers_with_aliases()

        {:noreply,
         socket
         |> assign(publishers: publishers, publishers_with_aliases: publishers_with_aliases)
         |> put_flash(:info, "Removed alias \"#{pub && pub.name}\"")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove alias")}
    end
  end

  @impl true
  def handle_info({:scan_progress, %{library_id: id, done: true}}, socket) do
    {:noreply, update(socket, :scanning_libraries, &MapSet.delete(&1, id))}
  end

  def handle_info({:scan_progress, %{library_id: id, scanned: s, total: t}}, socket) do
    {:noreply,
     update(socket, :scanning_libraries, fn libs ->
       if t > 0 and s < t, do: MapSet.put(libs, id), else: libs
     end)}
  end

  def handle_info({:clear_saved_perm, key}, socket) do
    {:noreply, update(socket, :saved_permissions, &MapSet.delete(&1, key))}
  end

  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.confirm_dialog confirm={@pending_confirm} />
    <div class="space-y-6">
      <%= if @live_action == :users do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-white">Users</h1>
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
                  <input
                    type="email"
                    name="email"
                    required
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                  />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Username</label>
                  <input
                    type="text"
                    name="username"
                    required
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                  />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Password</label>
                  <input
                    type="password"
                    name="password"
                    required
                    minlength="8"
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                  />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Role</label>
                  <select
                    name="role"
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                  >
                    <option value="user">User</option>
                    <option value="admin">Admin</option>
                  </select>
                </div>
                <div class="col-span-2 flex gap-2 justify-end">
                  <button
                    type="button"
                    phx-click="toggle_user_form"
                    class="px-3 py-1.5 text-sm text-gray-400 hover:text-white"
                  >Cancel</button>
                  <button
                    type="submit"
                    class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
                  >Create</button>
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
                  <% perm_open = @selected_perm_user_id == user.id
                  age_ratings = [:unknown, :everyone, :teen, :teen_plus, :mature, :adult, :explicit] %>
                  <tr class="border-b border-gray-800">
                    <td class="px-4 py-3 text-white">{user.username}</td>
                    <td class="px-4 py-3 text-gray-400">{user.email}</td>
                    <td class="px-4 py-3">
                      <span class={[
                        "px-2 py-0.5 rounded text-xs font-medium",
                        if(user.role == :admin,
                          do: "bg-indigo-900 text-indigo-300",
                          else: "bg-gray-800 text-gray-400"
                        )
                      ]}>
                        {user.role}
                      </span>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <div class="flex items-center gap-3 justify-end">
                        <%= if user.role != :admin do %>
                          <button
                            phx-click="show_user_permissions"
                            phx-value-id={user.id}
                            class={[
                              "text-xs transition-colors",
                              if(perm_open,
                                do: "text-indigo-400 hover:text-indigo-300",
                                else: "text-gray-400 hover:text-white"
                              )
                            ]}
                          >
                            Permissions
                          </button>
                        <% end %>
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
                      </div>
                    </td>
                  </tr>
                  <%= if perm_open do %>
                    <tr class="border-b border-gray-800 bg-gray-950">
                      <td colspan="4" class="px-4 py-4">
                        <div class="space-y-2">
                          <p class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-3">
                            Library Access for {user.username}
                          </p>
                          <%= if @libraries == [] do %>
                            <p class="text-sm text-gray-600">No libraries configured.</p>
                          <% else %>
                            <%= for lib <- @libraries do %>
                              <% perm = Map.get(@user_permissions, lib.id)
                              saved = MapSet.member?(@saved_permissions, "#{user.id}-#{lib.id}")
                              current_rating = if perm, do: perm.max_age_rating, else: :unknown

                              rating_opts =
                                Enum.map(age_ratings, &{Formatters.format_age_rating(&1), &1}) %>
                              <form
                                phx-change="set_permission"
                                class="flex items-center justify-between py-2 px-3 rounded-lg bg-gray-900 border border-gray-800"
                              >
                                <input type="hidden" name="user_id" value={user.id} />
                                <input type="hidden" name="library_id" value={lib.id} />
                                <div>
                                  <p class="text-sm text-white">{lib.name}</p>
                                  <p class="text-xs text-gray-600">{lib.root_path}</p>
                                </div>
                                <div class="flex items-center gap-4">
                                  <%= if saved do %>
                                    <span class="text-xs text-emerald-400 font-medium">✓ Saved</span>
                                  <% end %>
                                  <label class="flex items-center gap-2 cursor-pointer text-xs text-gray-400">
                                    <input
                                      type="checkbox"
                                      name="can_read"
                                      value="true"
                                      checked={perm != nil && perm.can_read}
                                      class="rounded border-gray-600 bg-gray-800 text-indigo-500 focus:ring-0 focus:ring-offset-0 cursor-pointer"
                                    /> Can read
                                  </label>
                                  <select
                                    id={"rating-#{user.id}-#{lib.id}-#{current_rating}"}
                                    name="max_age_rating"
                                    class="bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs text-gray-300 focus:outline-none focus:border-indigo-500"
                                  >
                                    {Phoenix.HTML.Form.options_for_select(rating_opts, current_rating)}
                                  </select>
                                </div>
                              </form>
                            <% end %>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <%= if @live_action == :libraries do %>
        <div class="space-y-4">
          <div class="flex items-center justify-between">
            <h1 class="text-2xl font-bold text-white">Libraries</h1>
            <div class="flex items-center gap-2">
              <button
                phx-click="backfill_blurhashes"
                class="px-3 py-1.5 bg-gray-800 hover:bg-gray-700 text-gray-300 text-sm rounded-lg border border-gray-700"
              >
                Backfill Blurhashes
              </button>
              <button
                phx-click="toggle_library_form"
                class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
              >
                Add Library
              </button>
            </div>
          </div>

          <%= if @show_library_form do %>
            <div class="bg-gray-900 border border-gray-700 rounded-xl p-6">
              <h3 class="text-white font-medium mb-4">Create Library</h3>
              <form phx-submit="create_library" class="space-y-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Name</label>
                  <input
                    type="text"
                    name="name"
                    required
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                    placeholder="My Comics"
                  />
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Root Path</label>
                  <input
                    type="text"
                    name="root_path"
                    required
                    class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-1.5 text-white text-sm focus:outline-none focus:border-indigo-500"
                    placeholder="/libraries/comics"
                  />
                </div>
                <div class="flex gap-2 justify-end">
                  <button
                    type="button"
                    phx-click="toggle_library_form"
                    class="px-3 py-1.5 text-sm text-gray-400 hover:text-white"
                  >Cancel</button>
                  <button
                    type="submit"
                    class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 text-white text-sm rounded-lg"
                  >Create</button>
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
                  <% scanning = MapSet.member?(@scanning_libraries, lib.id) %>
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
                      class={[
                        "px-3 py-1.5 text-sm rounded-lg border flex items-center gap-1.5",
                        if(scanning,
                          do: "bg-gray-900 text-gray-500 border-gray-800 cursor-not-allowed",
                          else: "bg-gray-800 hover:bg-gray-700 text-gray-300 border-gray-700"
                        )
                      ]}
                    >
                      <%= if scanning do %>
                        <.icon name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" /> Scanning...
                      <% else %>
                        Scan
                      <% end %>
                    </button>
                    <button
                      phx-click="force_scan_library"
                      phx-value-id={lib.id}
                      disabled={scanning}
                      class={[
                        "px-3 py-1.5 text-sm rounded-lg border",
                        if(scanning,
                          do: "bg-gray-900 text-gray-600 border-gray-800 cursor-not-allowed",
                          else: "bg-gray-800 hover:bg-gray-700 text-amber-400 border-gray-700"
                        )
                      ]}
                    >
                      Force Rescan
                    </button>
                    <button
                      phx-click="show_confirm"
                      phx-value-event="delete_library"
                      phx-value-id={lib.id}
                      phx-value-title="Delete Library"
                      phx-value-message={"Delete library \"#{lib.name}\" and ALL its books and series? Book files on disk are never deleted. This cannot be undone."}
                      phx-value-label="Delete"
                      class="px-3 py-1.5 text-sm rounded-lg border bg-gray-800 hover:bg-gray-700 text-red-400 border-gray-700"
                    >
                      Delete
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
                          placeholder="Default built-in: one-shot, one shot, oneshot\nAdd extras here, e.g.:\nAnnuals\nSpecials"
                        >{Enum.join(lib.standalone_folders, "\n")}</textarea>
                        <p class="text-xs text-gray-600 mt-1">
                          Built-in defaults (always active): <span class="text-gray-500">one-shot, one shot, oneshot</span>
                        </p>
                      </div>
                      <div class="flex gap-2 justify-end">
                        <button
                          type="button"
                          phx-click="cancel_edit_library"
                          class="px-3 py-1.5 text-sm text-gray-400 hover:text-white"
                        >Cancel</button>
                        <button
                          type="submit"
                          class="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-sm rounded-lg"
                        >Save</button>
                      </div>
                    </form>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @live_action == :cleanup do %>
        <% all_series_ids = Enum.map(@deleted_series, & &1.id) |> MapSet.new()
        all_books_ids = Enum.map(@deleted_books, & &1.id) |> MapSet.new()
        all_series_selected = @deleted_series != [] and @selected_series == all_series_ids
        all_books_selected = @deleted_books != [] and @selected_books == all_books_ids
        series_sel_count = MapSet.size(@selected_series)
        books_sel_count = MapSet.size(@selected_books) %>
        <div class="space-y-8">
          <h1 class="text-2xl font-bold text-white">Cleanup</h1>
          <%!-- Series section --%>
          <div class="space-y-3">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-white">
                Deleted Series <span class="ml-2 text-sm font-normal text-gray-500">({length(@deleted_series)})</span>
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
                    phx-value-message={"Permanently delete #{series_sel_count} series and ALL their books? Book files on disk are never deleted. This cannot be undone."}
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
                        <td class="px-4 py-3 text-gray-500 text-xs">
                          {Calendar.strftime(s.deleted_at, "%Y-%m-%d %H:%M")}
                        </td>
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
                            phx-value-message={"Permanently delete \"#{s.name}\" and all its books? Book files on disk are never deleted. This cannot be undone."}
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
                Deleted Books <span class="ml-2 text-sm font-normal text-gray-500">({length(@deleted_books)})</span>
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
                    phx-value-message={"Permanently delete #{books_sel_count} book(s)? Book files on disk are never deleted. This cannot be undone."}
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
                        <td class="px-4 py-3 text-gray-400">
                          {if b.series, do: b.series.name, else: "—"}
                        </td>
                        <td class="px-4 py-3 text-gray-400">{b.library.name}</td>
                        <td
                          class="px-4 py-3 text-gray-600 text-xs font-mono truncate max-w-xs"
                          title={b.path}
                        >
                          {b.path}
                        </td>
                        <td class="px-4 py-3 text-gray-500 text-xs">
                          {Calendar.strftime(b.deleted_at, "%Y-%m-%d %H:%M")}
                        </td>
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
                            phx-value-message={"Permanently delete \"#{b.title}\"? Book files on disk are never deleted. This cannot be undone."}
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
      <%= if @live_action == :publishers do %>
        <% alias_pub = Enum.find(@publishers, &(&1.id == @alias_source_id))
        master_pub = Enum.find(@publishers, &(&1.id == @alias_target_id)) %>
        <div class="space-y-6">
          <h1 class="text-2xl font-bold text-white">Publishers</h1>

          <%!-- Tab bar --%>
          <div class="flex gap-2 border-b border-gray-800">
            <%= for {label, tab} <- [{"Aliases", "aliases"}, {"Visibility", "visibility"}] do %>
              <.link
                patch={~p"/admin/publishers?tab=#{tab}"}
                class={[
                  "px-4 py-2 text-sm font-medium -mb-px border-b-2 transition-colors",
                  if(@publisher_tab == tab,
                    do: "border-violet-500 text-violet-400",
                    else: "border-transparent text-gray-500 hover:text-gray-300"
                  )
                ]}
              >
                {label}
              </.link>
            <% end %>
          </div>

          <%!-- Aliases tab --%>
          <%= if @publisher_tab == "aliases" do %>
            <div class="space-y-8 max-w-lg">
              <%!-- Set alias --%>
              <div class="space-y-4">
                <div>
                  <h2 class="text-base font-semibold text-white mb-1">Link Publisher Alias</h2>
                  <p class="text-sm text-gray-500">
                    Mark one publisher as an alias of another. The alias is hidden from listings and its content is shown under the master.
                  </p>
                </div>

                <%!-- Alias source picker --%>
                <div class="space-y-1.5">
                  <label class="text-xs font-medium text-gray-400 uppercase tracking-wide">Alias (will be hidden)</label>
                  <%= if @alias_source_id do %>
                    <% src = Enum.find(@publishers, &(&1.id == @alias_source_id)) %>
                    <div class="flex items-center justify-between bg-gray-900 border border-violet-600/50 rounded-lg px-3 py-2 text-sm">
                      <span class="text-white">{src && src.name}</span>
                      <button
                        phx-click="clear_alias_source"
                        class="text-gray-500 hover:text-white ml-2 flex-shrink-0"
                      >
                        <.icon name="lucide-x" class="w-4 h-4" />
                      </button>
                    </div>
                  <% else %>
                    <div class="relative">
                      <input
                        type="text"
                        value={@alias_source_query}
                        placeholder="Search publishers…"
                        phx-keyup="alias_source_input"
                        autocomplete="off"
                        class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
                      />
                      <%= if @alias_source_query != "" do %>
                        <% src_results =
                          @publishers
                          |> Enum.filter(
                            &String.contains?(
                              String.downcase(&1.name),
                              String.downcase(@alias_source_query)
                            )
                          )
                          |> Enum.take(8) %>
                        <div
                          class="absolute z-20 top-full left-0 right-0 mt-1 bg-gray-800 border border-gray-700 rounded-lg overflow-hidden shadow-xl"
                          onmousedown="event.preventDefault()"
                        >
                          <%= if src_results == [] do %>
                            <div class="px-3 py-2.5 text-sm text-gray-500">No publishers found</div>
                          <% else %>
                            <%= for {p, i} <- Enum.with_index(src_results) do %>
                              <button
                                phx-click="set_alias_source"
                                phx-value-id={p.id}
                                class={[
                                  "w-full text-left px-3 py-2 text-sm transition-colors",
                                  if(i == 0,
                                    do: "bg-gray-700/60 text-white hover:bg-gray-700",
                                    else: "text-gray-300 hover:bg-gray-700 hover:text-white"
                                  )
                                ]}
                              >{p.name}</button>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%!-- Alias target picker --%>
                <div class="space-y-1.5">
                  <label class="text-xs font-medium text-gray-400 uppercase tracking-wide">Master (kept, shown in listings)</label>
                  <%= if @alias_target_id do %>
                    <% tgt = Enum.find(@publishers, &(&1.id == @alias_target_id)) %>
                    <div class="flex items-center justify-between bg-gray-900 border border-violet-600/50 rounded-lg px-3 py-2 text-sm">
                      <span class="text-white">{tgt && tgt.name}</span>
                      <button
                        phx-click="clear_alias_target"
                        class="text-gray-500 hover:text-white ml-2 flex-shrink-0"
                      >
                        <.icon name="lucide-x" class="w-4 h-4" />
                      </button>
                    </div>
                  <% else %>
                    <div class="relative">
                      <input
                        type="text"
                        value={@alias_target_query}
                        placeholder="Search publishers…"
                        phx-keyup="alias_target_input"
                        autocomplete="off"
                        class="w-full bg-gray-900 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
                      />
                      <%= if @alias_target_query != "" do %>
                        <% tgt_results =
                          @publishers
                          |> Enum.reject(&(&1.id == @alias_source_id))
                          |> Enum.filter(
                            &String.contains?(
                              String.downcase(&1.name),
                              String.downcase(@alias_target_query)
                            )
                          )
                          |> Enum.take(8) %>
                        <div
                          class="absolute z-20 top-full left-0 right-0 mt-1 bg-gray-800 border border-gray-700 rounded-lg overflow-hidden shadow-xl"
                          onmousedown="event.preventDefault()"
                        >
                          <%= if tgt_results == [] do %>
                            <div class="px-3 py-2.5 text-sm text-gray-500">No publishers found</div>
                          <% else %>
                            <%= for {p, i} <- Enum.with_index(tgt_results) do %>
                              <button
                                phx-click="set_alias_target"
                                phx-value-id={p.id}
                                class={[
                                  "w-full text-left px-3 py-2 text-sm transition-colors",
                                  if(i == 0,
                                    do: "bg-gray-700/60 text-white hover:bg-gray-700",
                                    else: "text-gray-300 hover:bg-gray-700 hover:text-white"
                                  )
                                ]}
                              >{p.name}</button>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                </div>

                <%= if !@alias_pending do %>
                  <button
                    phx-click="preview_alias"
                    disabled={is_nil(@alias_source_id) || is_nil(@alias_target_id)}
                    class="px-4 py-2 bg-violet-600 hover:bg-violet-500 disabled:opacity-40 disabled:cursor-not-allowed text-white text-sm rounded-lg transition-colors"
                  >
                    Link as Alias
                  </button>
                <% else %>
                  <div class="rounded-lg border border-violet-800/60 bg-violet-950/30 p-4 space-y-3">
                    <p class="text-sm text-violet-300 font-medium">Confirm alias link</p>
                    <p class="text-sm text-gray-400">
                      <span class="text-white font-medium">"{alias_pub && alias_pub.name}"</span>
                      will become an alias of <span class="text-white font-medium">"{master_pub && master_pub.name}"</span>.
                      No data is deleted — this can be undone.
                    </p>
                    <div class="flex gap-2">
                      <button
                        phx-click="confirm_set_alias"
                        class="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white text-sm rounded-lg transition-colors"
                      >
                        Confirm
                      </button>
                      <button
                        phx-click="cancel_alias"
                        class="px-3 py-1.5 bg-gray-700 hover:bg-gray-600 text-white text-sm rounded-lg transition-colors"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>

              <%!-- Current aliases --%>
              <div>
                <h3 class="text-sm font-medium text-gray-400 mb-2">
                  Current aliases
                  <%= if @publishers_with_aliases != [] do %>
                    <span class="text-gray-600">({length(@publishers_with_aliases)})</span>
                  <% end %>
                </h3>
                <div class="rounded-lg border border-gray-800 overflow-hidden">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-gray-800 bg-gray-900/50">
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500">Master</th>
                        <th class="px-3 py-2 text-left text-xs font-medium text-gray-500">Alias</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-800">
                      <%= if @publishers_with_aliases == [] do %>
                        <tr>
                          <td colspan="3" class="px-3 py-4 text-center text-sm text-gray-600">
                            No aliases configured
                          </td>
                        </tr>
                      <% else %>
                        <%= for p <- @publishers_with_aliases do %>
                          <tr class="group hover:bg-gray-800/40 transition-colors">
                            <td class="px-3 py-2">
                              <a
                                href={~p"/publisher/#{p.canonical_publisher_id}"}
                                class="text-gray-300 hover:text-violet-300 transition-colors"
                              >
                                {p.canonical && p.canonical.name}
                              </a>
                            </td>
                            <td class="px-3 py-2">
                              <a
                                href={~p"/publisher/#{p.canonical_publisher_id}"}
                                class="text-gray-400 hover:text-violet-300 transition-colors"
                              >
                                {p.name}
                              </a>
                            </td>
                            <td class="px-3 py-2 text-right">
                              <button
                                phx-click="remove_alias"
                                phx-value-id={p.id}
                                class="text-xs text-red-500 hover:text-red-400"
                              >
                                Remove
                              </button>
                            </td>
                          </tr>
                        <% end %>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          <% end %>

          <%!-- Visibility tab --%>
          <%= if @publisher_tab == "visibility" do %>
            <% per_page = 50
            total_pages = max(1, ceil(@pub_vis_total / per_page)) %>
            <div class="space-y-3">
              <%!-- Search bar --%>
              <form phx-submit="pub_vis_search" class="max-w-sm">
                <div class="relative">
                  <.icon
                    name="lucide-search"
                    class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-500 pointer-events-none"
                  />
                  <input
                    type="search"
                    name="q"
                    value={@pub_vis_search}
                    placeholder="Filter publishers…"
                    autocomplete="off"
                    phx-change="pub_vis_search"
                    phx-debounce="200"
                    class="w-full bg-gray-900 border border-gray-800 rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500/70"
                  />
                </div>
              </form>

              <%!-- Count + top pagination --%>
              <div class="flex items-center justify-between">
                <p class="text-xs text-gray-500">
                  {@pub_vis_total} publisher{if @pub_vis_total == 1, do: "", else: "s"}
                  <%= if @pub_vis_search != "" do %>
                    matching <span class="text-gray-400">"{@pub_vis_search}"</span>
                  <% end %>
                </p>
                <%= if total_pages > 1 do %>
                  <div class="flex gap-1">
                    <button
                      phx-click="pub_vis_page"
                      phx-value-page={@pub_vis_page - 1}
                      disabled={@pub_vis_page <= 1}
                      class="px-2.5 py-1 rounded text-sm text-gray-400 bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                    >‹</button>
                    <%= for pg <- max(1, @pub_vis_page - 2)..min(total_pages, @pub_vis_page + 2) do %>
                      <button
                        phx-click="pub_vis_page"
                        phx-value-page={pg}
                        class={[
                          "px-2.5 py-1 rounded text-sm border transition-colors",
                          if(pg == @pub_vis_page,
                            do: "bg-violet-600 border-violet-500 text-white",
                            else: "bg-gray-800 border-gray-700 text-gray-400 hover:bg-gray-700"
                          )
                        ]}
                      >{pg}</button>
                    <% end %>
                    <button
                      phx-click="pub_vis_page"
                      phx-value-page={@pub_vis_page + 1}
                      disabled={@pub_vis_page >= total_pages}
                      class="px-2.5 py-1 rounded text-sm text-gray-400 bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                    >›</button>
                  </div>
                <% end %>
              </div>

              <div class="rounded-lg border border-gray-800 overflow-hidden">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="border-b border-gray-800 bg-gray-900/50">
                      <th class="px-3 py-2 text-left text-xs font-medium text-gray-500">Name</th>
                      <th class="px-3 py-2 text-left text-xs font-medium text-gray-500">Status</th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-500">Series</th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-500">Books</th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-500">Issues</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-800">
                    <%= for p <- @pub_vis_publishers do %>
                      <% stats =
                        Map.get(@pub_vis_stats, p.id, %{
                          series_count: 0,
                          books_count: 0,
                          issues_count: 0
                        })

                      master_hidden = p.canonical && p.canonical.hidden
                      effectively_hidden = p.hidden || master_hidden %>
                      <tr class="group hover:bg-gray-800/40 transition-colors">
                        <td class="px-3 py-2">
                          <a
                            href={~p"/publisher/#{p.id}"}
                            class={"hover:text-violet-300 transition-colors #{if effectively_hidden, do: "text-gray-600 line-through", else: "text-gray-300"}"}
                          >
                            {p.name}
                          </a>
                        </td>
                        <td class="px-3 py-2">
                          <%= cond do %>
                            <% p.hidden -> %>
                              <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-gray-700">Hidden</span>
                            <% master_hidden -> %>
                              <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-gray-700">Alias · Hidden</span>
                            <% not is_nil(p.canonical_publisher_id) -> %>
                              <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-gray-700">Alias</span>
                            <% true -> %>
                              <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-violet-900/30 text-violet-400 border border-violet-800/40">Visible</span>
                          <% end %>
                        </td>
                        <td class="px-3 py-2 text-right text-gray-500 tabular-nums">
                          {stats.series_count}
                        </td>
                        <td class="px-3 py-2 text-right text-gray-500 tabular-nums">
                          {stats.books_count}
                        </td>
                        <td class="px-3 py-2 text-right text-gray-500 tabular-nums">
                          {stats.issues_count}
                        </td>
                        <td class="px-3 py-2 text-right">
                          <%= if is_nil(p.canonical_publisher_id) do %>
                            <button
                              phx-click="toggle_publisher_hidden"
                              phx-value-id={p.id}
                              class={"text-xs transition-colors #{if p.hidden, do: "text-violet-400 hover:text-violet-300", else: "text-gray-500 hover:text-red-400"}"}
                            >
                              {if p.hidden, do: "Show", else: "Hide"}
                            </button>
                          <% end %>
                        </td>
                      </tr>
                    <% end %>
                    <%= if @pub_vis_publishers == [] do %>
                      <tr>
                        <td colspan="6" class="px-3 py-6 text-center text-sm text-gray-600">
                          No publishers found
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <%!-- Bottom pagination --%>
              <%= if total_pages > 1 do %>
                <div class="flex items-center justify-between pt-1">
                  <p class="text-xs text-gray-500">Page {@pub_vis_page} of {total_pages}</p>
                  <div class="flex gap-1">
                    <button
                      phx-click="pub_vis_page"
                      phx-value-page={@pub_vis_page - 1}
                      disabled={@pub_vis_page <= 1}
                      class="px-2.5 py-1 rounded text-sm text-gray-400 bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                    >‹</button>
                    <%= for pg <- max(1, @pub_vis_page - 2)..min(total_pages, @pub_vis_page + 2) do %>
                      <button
                        phx-click="pub_vis_page"
                        phx-value-page={pg}
                        class={[
                          "px-2.5 py-1 rounded text-sm border transition-colors",
                          if(pg == @pub_vis_page,
                            do: "bg-violet-600 border-violet-500 text-white",
                            else: "bg-gray-800 border-gray-700 text-gray-400 hover:bg-gray-700"
                          )
                        ]}
                      >{pg}</button>
                    <% end %>
                    <button
                      phx-click="pub_vis_page"
                      phx-value-page={@pub_vis_page + 1}
                      disabled={@pub_vis_page >= total_pages}
                      class="px-2.5 py-1 rounded text-sm text-gray-400 bg-gray-800 border border-gray-700 hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                    >›</button>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
