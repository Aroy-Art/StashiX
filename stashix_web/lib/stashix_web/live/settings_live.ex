defmodule StashixWeb.SettingsLive do
  @moduledoc """
  A user's own settings, in three tabs: UI (appearance), Personal (name and
  birth date) and Security (email, password, sessions).

  The Security forms post to `StashixWeb.SettingsController`, because they
  have to rewrite the session cookie; everything else is handled here.
  """
  use StashixWeb, :live_view

  alias Stashix.Accounts
  alias Stashix.Accounts.{Session, User}
  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Settings",
       preview_covers: preview_covers(socket),
       current_session_id: session["session_id"],
       sessions: []
     )
     |> assign_profile_form(User.profile_changeset(socket.assigns.current_user, %{}))}
  end

  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :security}} = socket) do
    {:noreply, assign_sessions(socket)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_ui", params, socket) do
    attrs = Map.take(params, Map.keys(User.ui_choices()))

    case Accounts.update_ui_settings(socket.assigns.current_user, attrs) do
      {:ok, user} -> {:noreply, assign(socket, current_user: user)}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "That is not one of the choices.")}
    end
  end

  def handle_event("validate_profile", %{"profile" => params}, socket) do
    changeset = socket.assigns.current_user |> User.profile_changeset(params) |> Map.put(:action, :validate)
    {:noreply, assign_profile_form(socket, changeset)}
  end

  def handle_event("save_profile", %{"profile" => params}, socket) do
    case Accounts.update_profile(socket.assigns.current_user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user)
         |> assign_profile_form(User.profile_changeset(user, %{}))
         |> put_flash(:info, "Profile saved.")}

      {:error, changeset} ->
        {:noreply, assign_profile_form(socket, changeset)}
    end
  end

  # The current session is left alone: ending it is what the sign-out menu is for.
  def handle_event("revoke_session", %{"id" => id}, socket) do
    if id != socket.assigns.current_session_id, do: Accounts.revoke_session(socket.assigns.current_user, id)
    {:noreply, assign_sessions(socket)}
  end

  # Scan broadcasts reach every page through the sidebar subscriptions.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # This browser first, then the rest as listed: most recently used first.
  defp assign_sessions(socket) do
    sessions =
      socket.assigns.current_user
      |> Accounts.list_sessions()
      |> Enum.sort_by(&(&1.id != socket.assigns.current_session_id))

    assign(socket, sessions: sessions)
  end

  defp assign_profile_form(socket, changeset), do: assign(socket, profile_form: to_form(changeset, as: :profile))

  # Real covers make the read-mark preview honest: one random book per choice,
  # the same one twice when the library only has one. Picked on the connected
  # mount only, so the covers do not change between the first paint and the
  # socket connecting.
  defp preview_covers(socket) do
    if connected?(socket) do
      case Library.random_cover_book_ids(socket.assigns.access, 2) do
        [] -> %{}
        [only] -> %{"check" => cover_path(only), "stamp" => cover_path(only)}
        [first, second] -> %{"check" => cover_path(first), "stamp" => cover_path(second)}
      end
    else
      %{}
    end
  end

  defp cover_path(book_id), do: ~p"/api/books/#{book_id}/cover"

  defp last_seen(%Session{last_seen_at: at}) do
    case DateTime.diff(DateTime.utc_now(), at, :minute) do
      minutes when minutes < 10 -> "Active now"
      minutes when minutes < 60 -> "Active #{minutes} min ago"
      minutes when minutes < 60 * 24 -> "Active #{div(minutes, 60)} h ago"
      minutes when minutes < 60 * 48 -> "Active yesterday"
      minutes -> "Active #{div(minutes, 60 * 24)} days ago"
    end
  end

  defp field_error(form, field) do
    case form[field].errors do
      [{message, opts} | _] ->
        Enum.reduce(opts, message, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
        end)

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_hero title="Settings" eyebrow={@current_user.display_name || @current_user.username} />

      <.tabs label="Settings sections">
        <:tab patch={~p"/settings"} active={@live_action == :ui}>UI</:tab>
        <:tab patch={~p"/settings/personal"} active={@live_action == :personal}>Personal</:tab>
        <:tab patch={~p"/settings/security"} active={@live_action == :security}>Security</:tab>
      </.tabs>

      <.ui_tab :if={@live_action == :ui} current_user={@current_user} preview_covers={@preview_covers} />
      <.personal_tab :if={@live_action == :personal} form={@profile_form} current_user={@current_user} />
      <.security_tab
        :if={@live_action == :security}
        current_user={@current_user}
        sessions={@sessions}
        current_session_id={@current_session_id}
      />
    </.page>
    """
  end

  attr :current_user, :map, required: true
  attr :preview_covers, :map, default: %{}

  defp ui_tab(assigns) do
    assigns = assign(assigns, read_mark: User.ui_setting(assigns.current_user, "read_mark"))

    ~H"""
    <.section title="Read mark">
      <p class="max-w-xl -mt-1 mb-5 text-sm text-gray-400">
        How a finished book is marked on its cover. Applies everywhere covers are shown, on this account only.
      </p>
      <form id="ui-settings" phx-change="set_ui" class="grid grid-cols-2 gap-4 max-w-md">
        <label
          :for={
            {value, name, blurb} <- [
              {"check", "Tick", "A small green tick in the corner."},
              {"stamp", "Stamp", "A READ stamp across the cover."}
            ]
          }
          class="choice-card group relative block p-3 rounded-md bg-gray-900 ring-1 ring-white/10 cursor-pointer transition-shadow"
        >
          <input type="radio" name="read_mark" value={value} checked={@read_mark == value} class="sr-only" />
          <div class="pointer-events-none" aria-hidden="true">
            <.media_card
              navigate="#"
              title=""
              cover_url={@preview_covers[value]}
              size="m"
              progress={1.0}
              read_mark={value}
              scope={"preview-#{value}"}
            />
          </div>
          <p class="mt-1 font-display font-black uppercase text-xl leading-none text-white">{name}</p>
          <p class="mt-1 text-xs text-gray-400">{blurb}</p>
          <.sticker size="xs" tilt={false} class="choice-card-on absolute top-2 right-2">On</.sticker>
        </label>
      </form>
    </.section>
    """
  end

  attr :form, :map, required: true
  attr :current_user, :map, required: true

  defp personal_tab(assigns) do
    ~H"""
    <.section title="About you">
      <.form
        for={@form}
        id="profile-form"
        phx-change="validate_profile"
        phx-submit="save_profile"
        class="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl"
      >
        <.field
          label="Display name"
          hint="Shown in the top bar instead of your username."
          error={field_error(@form, :display_name)}
        >
          <.text_input name="profile[display_name]" value={@form[:display_name].value} autocomplete="name" />
        </.field>
        <.field label="Username" hint="What you sign in with." required error={field_error(@form, :username)}>
          <.text_input name="profile[username]" value={@form[:username].value} required autocomplete="username" />
        </.field>
        <.field label="Birth date" error={field_error(@form, :birth_date)}>
          <.text_input type="date" name="profile[birth_date]" value={@form[:birth_date].value} />
        </.field>
        <div class="sm:col-span-2 flex items-center gap-4 pt-1">
          <.ink_button type="submit" size="md">Save profile</.ink_button>
          <p class="text-xs text-gray-400">
            Email and password are under <.link
              patch={~p"/settings/security"}
              class="underline underline-offset-4 hover:text-white"
            >Security</.link>.
          </p>
        </div>
      </.form>
    </.section>

    <.panel variant="indicia">
      <.stat_list class="px-6 py-5">
        <.stat label="Role">{@current_user.role}</.stat>
        <.stat label="Email">{@current_user.email}</.stat>
        <.stat label="Member since">{Calendar.strftime(@current_user.inserted_at, "%b %Y")}</.stat>
      </.stat_list>
    </.panel>
    """
  end

  attr :current_user, :map, required: true
  attr :sessions, :list, required: true
  attr :current_session_id, :string, default: nil

  defp security_tab(assigns) do
    assigns = assign(assigns, csrf: Plug.CSRFProtection.get_csrf_token())

    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-start">
      <.panel class="p-5 sm:p-6">
        <.display_heading size="panel" class="mb-1">Password</.display_heading>
        <p class="mb-5 text-sm text-gray-400">Changing it signs you out on every other device.</p>
        <form id="password-form" method="post" action={~p"/settings/password"} class="space-y-4">
          <input type="hidden" name="_csrf_token" value={@csrf} />
          <.field label="Current password">
            <.text_input type="password" name="current_password" required autocomplete="current-password" />
          </.field>
          <.field label="New password" hint="At least 8 characters.">
            <.text_input type="password" name="password" required minlength="8" autocomplete="new-password" />
          </.field>
          <.field label="Repeat new password">
            <.text_input
              type="password"
              name="password_confirmation"
              required
              minlength="8"
              autocomplete="new-password"
            />
          </.field>
          <.ink_button type="submit" size="md">Change password</.ink_button>
        </form>
      </.panel>

      <div class="space-y-6">
        <.panel class="p-5 sm:p-6">
          <.display_heading size="panel" class="mb-1">Email</.display_heading>
          <p class="mb-5 text-sm text-gray-400">
            Currently <span class="font-semibold text-gray-200">{@current_user.email}</span>.
          </p>
          <form id="email-form" method="post" action={~p"/settings/email"} class="space-y-4">
            <input type="hidden" name="_csrf_token" value={@csrf} />
            <.field label="New email">
              <.text_input type="email" name="email" required autocomplete="email" />
            </.field>
            <.field label="Current password">
              <.text_input type="password" name="current_password" required autocomplete="current-password" />
            </.field>
            <.ink_button type="submit" size="md">Change email</.ink_button>
          </form>
        </.panel>

        <.panel class="p-5 sm:p-6">
          <.display_heading size="panel" class="mb-1">Sessions</.display_heading>
          <p class="mb-4 text-sm text-gray-400">Where this account is signed in.</p>
          <ul :if={@sessions != []} id="sessions" class="mb-5 border-y border-white/10 divide-y divide-white/10">
            <li :for={session <- @sessions} class="flex items-center justify-between gap-3 py-3">
              <div class="min-w-0">
                <p class="font-display font-bold uppercase text-lg leading-tight tracking-wide text-white truncate">
                  {Session.device(session)}
                </p>
                <p class="text-xs text-gray-400">
                  {last_seen(session)} · signed in {Calendar.strftime(session.inserted_at, "%-d %b %Y")}
                </p>
              </div>
              <.sticker :if={session.id == @current_session_id} size="xs" tilt={false} class="shrink-0 uppercase">
                This one
              </.sticker>
              <.ink_button
                :if={session.id != @current_session_id}
                variant="ghost"
                size="md"
                class="shrink-0"
                phx-click="revoke_session"
                phx-value-id={session.id}
                aria-label={"Sign out #{Session.device(session)}"}
              >
                Sign out
              </.ink_button>
            </li>
          </ul>
          <p :if={@sessions == []} id="sessions-empty" class="mb-5 text-sm text-gray-500">
            None recorded yet. Sign-ins from before this list existed show up once they sign in again.
          </p>
          <p class="mb-5 text-sm text-gray-400">
            Left a device signed in? This signs the account out of every browser and app except this one.
          </p>
          <form id="sessions-form" method="post" action={~p"/settings/sessions/revoke"}>
            <input type="hidden" name="_csrf_token" value={@csrf} />
            <.ink_button type="submit" size="md" variant="warning">
              <.icon name="lucide-log-out" class="w-4 h-4" /> Sign out everywhere else
            </.ink_button>
          </form>
        </.panel>
      </div>
    </div>
    """
  end
end
