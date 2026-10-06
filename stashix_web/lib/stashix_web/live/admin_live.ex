defmodule StashixWeb.AdminLive do
  use StashixWeb, :live_view

  alias Stashix.{Accounts, Library}
  alias StashixWeb.AdminLive.{Cleanup, Libraries, Publishers, Users}

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
    |> assign(:publishers, Library.list_publishers(Stashix.Library.Access.all()))
    |> assign(:publishers_with_aliases, Library.list_publishers_with_aliases())
    |> load_vis_publishers()
  end

  defp load_vis_publishers(socket) do
    search = socket.assigns[:pub_vis_search] || ""
    page = socket.assigns[:pub_vis_page] || 1
    {pubs, total} = Library.list_all_publishers_admin(search: search, page: page, limit: 50)
    stats = Library.publisher_stats(Stashix.Library.Access.all(), Enum.map(pubs, & &1.id))

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
           role: role
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

      case Accounts.delete_user(user) do
        {:ok, _} -> {:noreply, assign(socket, :users, Accounts.list_users())}
        {:error, :last_admin} -> {:noreply, put_flash(socket, :error, "Cannot delete the last admin")}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete user")}
      end
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

  def handle_event("match_library_metadata", %{"id" => id}, socket) do
    case Stashix.Metadata.enqueue_library(id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Metadata matching queued — follow progress in Admin · Metadata · Jobs")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not queue metadata matching")}
    end
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
    hide_unrated = Map.get(params, "hide_unrated") == "true"

    attrs = %{
      user_id: user_id,
      library_id: library_id,
      can_read: can_read,
      max_age_rating: max_age_rating,
      hide_unrated: hide_unrated
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
           publishers: Library.list_publishers(Stashix.Library.Access.all()),
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
        publishers = Library.list_publishers(Stashix.Library.Access.all())

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
        publishers = Library.list_publishers(Stashix.Library.Access.all())
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
  def handle_info({:cover_updated, _}, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.confirm_dialog confirm={@pending_confirm} />
    <.page wide>
      <Users.tab
        :if={@live_action == :users}
        current_user={@current_user}
        libraries={@libraries}
        saved_permissions={@saved_permissions}
        selected_perm_user_id={@selected_perm_user_id}
        show_user_form={@show_user_form}
        user_permissions={@user_permissions}
        users={@users}
      />
      <Libraries.tab
        :if={@live_action == :libraries}
        editing_library_id={@editing_library_id}
        libraries={@libraries}
        scanning_libraries={@scanning_libraries}
        show_library_form={@show_library_form}
      />
      <Cleanup.tab
        :if={@live_action == :cleanup}
        deleted_books={@deleted_books}
        deleted_series={@deleted_series}
        selected_books={@selected_books}
        selected_series={@selected_series}
      />
      <Publishers.tab
        :if={@live_action == :publishers}
        alias_pending={@alias_pending}
        alias_source_id={@alias_source_id}
        alias_source_query={@alias_source_query}
        alias_target_id={@alias_target_id}
        alias_target_query={@alias_target_query}
        pub_vis_page={@pub_vis_page}
        pub_vis_publishers={@pub_vis_publishers}
        pub_vis_search={@pub_vis_search}
        pub_vis_stats={@pub_vis_stats}
        pub_vis_total={@pub_vis_total}
        publisher_tab={@publisher_tab}
        publishers={@publishers}
        publishers_with_aliases={@publishers_with_aliases}
      />
    </.page>
    """
  end
end
