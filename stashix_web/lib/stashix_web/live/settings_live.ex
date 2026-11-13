# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SettingsLive do
  @moduledoc """
  A user's own settings, in tabs: UI (appearance), Personal (name and birth
  date), Security (email, password, sessions) and About (version, license and
  the source link the AGPL asks for).

  The Security forms post to `StashixWeb.SettingsController`, because they
  have to rewrite the session cookie; everything else is handled here.
  """
  use StashixWeb, :live_view

  import StashixWeb.DetailComponents

  alias Stashix.Accounts
  alias Stashix.Accounts.{Session, User}
  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: gettext("Settings"),
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
      {:ok, user} -> {:noreply, socket |> assign(current_user: user) |> StashixWeb.Live.Hooks.push_theme()}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, gettext("That is not one of the choices."))}
    end
  end

  # The locale is read on a full page load (StashixWeb.Locale), so reload.
  def handle_event("set_locale", %{"locale" => locale}, socket) do
    case Accounts.update_ui_settings(socket.assigns.current_user, %{"locale" => locale}) do
      {:ok, _user} -> {:noreply, redirect(socket, to: ~p"/settings")}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, gettext("That is not one of the choices."))}
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
         |> put_flash(:info, gettext("Profile saved."))}

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
      minutes when minutes < 10 -> gettext("Active now")
      minutes when minutes < 60 -> gettext("Active %{count} min ago", count: minutes)
      minutes when minutes < 60 * 24 -> gettext("Active %{count} h ago", count: div(minutes, 60))
      minutes when minutes < 60 * 48 -> gettext("Active yesterday")
      minutes -> ngettext("Active 1 day ago", "Active %{count} days ago", div(minutes, 60 * 24))
    end
  end

  defp role_label(:admin), do: gettext("Admin")
  defp role_label(:user), do: gettext("User")

  defp stale?(%Session{last_seen_at: at}) do
    DateTime.diff(DateTime.utc_now(), at, :day) >= 30
  end

  defp field_error(form, field) do
    case form[field].errors do
      [error | _] ->
        translate_error(error)

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_hero title={gettext("Settings")} eyebrow={@current_user.display_name || @current_user.username} />

      <.tabs label={gettext("Settings sections")}>
        <:tab patch={~p"/settings"} active={@live_action == :ui}>{gettext("UI")}</:tab>
        <:tab patch={~p"/settings/personal"} active={@live_action == :personal}>{gettext("Personal")}</:tab>
        <:tab patch={~p"/settings/security"} active={@live_action == :security}>{gettext("Security")}</:tab>
        <:tab patch={~p"/settings/about"} active={@live_action == :about}>{gettext("About")}</:tab>
      </.tabs>

      <.ui_tab :if={@live_action == :ui} current_user={@current_user} preview_covers={@preview_covers} />
      <.personal_tab :if={@live_action == :personal} form={@profile_form} current_user={@current_user} />
      <.security_tab
        :if={@live_action == :security}
        current_user={@current_user}
        sessions={@sessions}
        current_session_id={@current_session_id}
      />
      <.about_tab :if={@live_action == :about} />
    </.page>
    """
  end

  attr :current_user, :map, required: true

  defp language_section(assigns) do
    assigns =
      assign(assigns,
        locale: User.locale(assigns.current_user),
        options: [{gettext("Automatic"), "auto"} | Enum.map(User.locales(), &{StashixWeb.Locale.name(&1), &1})]
      )

    ~H"""
    <.section title={gettext("Language")}>
      <p class="max-w-xl -mt-1 mb-5 text-sm text-muted">
        {gettext("Automatic follows your browser's language. Saved to your account, so it follows you to other devices.")}
      </p>
      <form id="ui-settings-locale" phx-change="set_locale" class="max-w-xs">
        <.ink_select
          id="ui-settings-locale-select"
          name="locale"
          value={@locale}
          options={@options}
          label={gettext("Language")}
          variant="field"
          align="start"
        />
      </form>
    </.section>
    """
  end

  attr :current_user, :map, required: true
  attr :preview_covers, :map, default: %{}

  defp ui_tab(assigns) do
    assigns =
      assign(assigns,
        theme: User.ui_setting(assigns.current_user, "theme"),
        read_mark: User.ui_setting(assigns.current_user, "read_mark"),
        extended_book_info: User.ui_setting(assigns.current_user, "extended_book_info"),
        data_saver: User.ui_setting(assigns.current_user, "data_saver")
      )

    ~H"""
    <.language_section current_user={@current_user} />

    <.section title={gettext("Theme")}>
      <p class="max-w-xl -mt-1 mb-5 text-sm text-muted">
        {gettext(
          "System follows your device's light or dark setting. Saved to your account, so it follows you to other devices."
        )}
      </p>
      <form id="ui-settings-theme" phx-change="set_ui" class="grid grid-cols-3 gap-4 max-w-xl">
        <label
          :for={
            {value, name, icon, scheme} <- [
              {"system", gettext("System"), "lucide-monitor", "scheme-light-dark"},
              {"light", gettext("Light"), "lucide-sun", "scheme-light"},
              {"dark", gettext("Dark"), "lucide-moon", "scheme-dark"}
            ]
          }
          class="choice-card group relative block p-3 rounded-md bg-surface ring-1 ring-edge cursor-pointer transition-shadow"
        >
          <input type="radio" name="theme" value={value} checked={@theme == value} class="sr-only" />
          <%!-- A tiny page in that theme: canvas, a card and two lines of text. --%>
          <div class={[scheme, "pointer-events-none p-2 rounded-sm bg-canvas ring-1 ring-edge"]} aria-hidden="true">
            <div class="p-2 rounded-sm bg-surface ring-1 ring-edge space-y-1.5">
              <div class="h-1.5 w-2/3 rounded-full bg-fg"></div>
              <div class="h-1.5 w-1/2 rounded-full bg-muted"></div>
              <div class="h-1.5 w-1/3 rounded-full bg-ink"></div>
            </div>
          </div>
          <p class="mt-2 flex items-center gap-1.5 font-display font-black uppercase text-xl leading-none text-fg">
            <.icon name={icon} class="w-4 h-4 text-muted" />{name}
          </p>
          <.sticker size="xs" tilt={false} class="choice-card-on absolute top-2 right-2">{gettext("On")}</.sticker>
        </label>
      </form>
    </.section>

    <.section title={gettext("Read mark")}>
      <p class="max-w-xl -mt-1 mb-5 text-sm text-muted">
        {gettext("How a finished book is marked on its cover. Applies everywhere covers are shown, on this account only.")}
      </p>
      <form id="ui-settings" phx-change="set_ui" class="grid grid-cols-2 gap-4 max-w-md">
        <label
          :for={
            {value, name, blurb} <- [
              {"check", gettext("Tick"), gettext("A small green tick in the corner.")},
              {"stamp", gettext("Stamp"), gettext("A READ stamp across the cover.")}
            ]
          }
          class="choice-card group relative block p-3 rounded-md bg-surface ring-1 ring-edge cursor-pointer transition-shadow"
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
          <p class="mt-1 font-display font-black uppercase text-xl leading-none text-fg">{name}</p>
          <p class="mt-1 text-xs text-muted">{blurb}</p>
          <.sticker size="xs" tilt={false} class="choice-card-on absolute top-2 right-2">{gettext("On")}</.sticker>
        </label>
      </form>
    </.section>

    <.section title={gettext("Book info")}>
      <p class="max-w-xl -mt-1 mb-5 text-sm text-muted">
        {gettext("Show file size and format on book and series pages. Off by default.")}
      </p>
      <form id="ui-settings-extended" phx-change="set_ui" class="flex flex-col gap-5 max-w-xl">
        <label class="inline-flex items-center gap-3 cursor-pointer select-none">
          <input type="hidden" name="extended_book_info" value="off" />
          <input
            type="checkbox"
            name="extended_book_info"
            value="on"
            checked={@extended_book_info == "on"}
            class="sr-only peer"
          />
          <span class="relative w-10 h-6 rounded-full bg-strong ring-1 ring-edge peer-checked:bg-violet-600 transition-colors after:absolute after:top-1 after:left-1 after:w-4 after:h-4 after:rounded-full after:bg-white after:transition-transform peer-checked:after:translate-x-4"></span>
          <span class="text-sm text-fg-soft">{gettext("Show extended book info")}</span>
        </label>
        <.indicia>
          <:item label={gettext("Publisher")}>Image Comics</:item>
          <:item label={gettext("Format")} show={@extended_book_info == "on"}>CBZ</:item>
          <:item label={gettext("Size")} show={@extended_book_info == "on"}>47.3 MB</:item>
          <:item label={gettext("Language")}>{gettext("English")}</:item>
          <:item label={gettext("Age Rating")}>{gettext("Mature")}</:item>
        </.indicia>
      </form>
    </.section>

    <form id="ui-settings-data-saver" phx-change="set_ui" class="max-w-xl">
      <label class="inline-flex items-center gap-3 cursor-pointer select-none">
        <input type="hidden" name="data_saver" value="off" />
        <input type="checkbox" name="data_saver" value="on" checked={@data_saver == "on"} class="sr-only peer" />
        <span class="relative w-10 h-6 rounded-full bg-strong ring-1 ring-edge peer-checked:bg-violet-600 transition-colors after:absolute after:top-1 after:left-1 after:w-4 after:h-4 after:rounded-full after:bg-white after:transition-transform peer-checked:after:translate-x-4"></span>
        <span class="font-display font-black uppercase text-xl leading-none text-fg">{gettext("Data saver")}</span>
      </label>
      <p class="mt-3 text-sm text-muted">
        {gettext(
          "Minimizes data usage by preventing automatic prefetching (e.g., upcoming reader pages and covers on hover)."
        )}
      </p>
    </form>
    """
  end

  attr :form, :map, required: true
  attr :current_user, :map, required: true

  defp personal_tab(assigns) do
    ~H"""
    <.section title={gettext("About you")}>
      <.form
        for={@form}
        id="profile-form"
        phx-change="validate_profile"
        phx-submit="save_profile"
        class="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl"
      >
        <.field
          label={gettext("Display name")}
          hint={gettext("Shown in the top bar instead of your username.")}
          error={field_error(@form, :display_name)}
        >
          <.text_input name="profile[display_name]" value={@form[:display_name].value} autocomplete="name" />
        </.field>
        <.field
          label={gettext("Username")}
          hint={gettext("What you sign in with.")}
          required
          error={field_error(@form, :username)}
        >
          <.text_input name="profile[username]" value={@form[:username].value} required autocomplete="username" />
        </.field>
        <.field label={gettext("Birth date")} error={field_error(@form, :birth_date)}>
          <.text_input type="date" name="profile[birth_date]" value={@form[:birth_date].value} />
        </.field>
        <div class="sm:col-span-2 flex items-center gap-4 pt-1">
          <.ink_button type="submit" size="md">{gettext("Save profile")}</.ink_button>
          <p class="text-xs text-muted">
            <.rich_text text={gettext("Email and password are under %{security}.", security: rich_marker("security"))}>
              <:part name="security">
                <.link
                  patch={~p"/settings/security"}
                  class="underline underline-offset-4 hover:text-fg"
                >{gettext("Security")}</.link>
              </:part>
            </.rich_text>
          </p>
        </div>
      </.form>
    </.section>

    <.panel variant="indicia">
      <.stat_list class="px-6 py-5">
        <.stat label={gettext("Role")}>{role_label(@current_user.role)}</.stat>
        <.stat label={gettext("Email")}>{@current_user.email}</.stat>
        <.stat label={gettext("Member since")}>
          <.local_time id="member-since" value={@current_user.inserted_at} format="month_short" />
        </.stat>
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
        <.display_heading size="panel" class="mb-1">{gettext("Password")}</.display_heading>
        <p class="mb-5 text-sm text-muted">{gettext("Changing it signs you out on every other device.")}</p>
        <form id="password-form" method="post" action={~p"/settings/password"} class="space-y-4">
          <input type="hidden" name="_csrf_token" value={@csrf} />
          <.field label={gettext("Current password")}>
            <.text_input type="password" name="current_password" required autocomplete="current-password" />
          </.field>
          <.field label={gettext("New password")} hint={gettext("At least 8 characters.")}>
            <.text_input type="password" name="password" required minlength="8" autocomplete="new-password" />
          </.field>
          <.field label={gettext("Repeat new password")}>
            <.text_input
              type="password"
              name="password_confirmation"
              required
              minlength="8"
              autocomplete="new-password"
            />
          </.field>
          <.ink_button type="submit" size="md">{gettext("Change password")}</.ink_button>
        </form>
      </.panel>

      <div class="space-y-6">
        <.panel class="p-5 sm:p-6">
          <.display_heading size="panel" class="mb-1">{gettext("Email")}</.display_heading>
          <p class="mb-5 text-sm text-muted">
            <.rich_text text={gettext("Currently %{email}.", email: rich_marker("email"))}>
              <:part name="email"><span class="font-semibold text-fg-soft">{@current_user.email}</span></:part>
            </.rich_text>
          </p>
          <form id="email-form" method="post" action={~p"/settings/email"} class="space-y-4">
            <input type="hidden" name="_csrf_token" value={@csrf} />
            <.field label={gettext("New email")}>
              <.text_input type="email" name="email" required autocomplete="email" />
            </.field>
            <.field label={gettext("Current password")}>
              <.text_input type="password" name="current_password" required autocomplete="current-password" />
            </.field>
            <.ink_button type="submit" size="md">{gettext("Change email")}</.ink_button>
          </form>
        </.panel>

        <.panel class="p-5 sm:p-6">
          <.display_heading size="panel" class="mb-1">{gettext("Sessions")}</.display_heading>
          <p class="mb-4 text-sm text-muted">{gettext("Where this account is signed in.")}</p>
          <ul :if={@sessions != []} id="sessions" class="mb-5 border-y border-fg/10 divide-y divide-fg/10">
            <li
              :for={session <- @sessions}
              class={["flex items-center justify-between gap-3 py-3", stale?(session) && "opacity-60"]}
            >
              <div class="min-w-0">
                <p class={[
                  "font-display font-bold uppercase text-lg leading-tight tracking-wide truncate",
                  stale?(session) && "text-danger line-through decoration-danger/50",
                  !stale?(session) && "text-fg"
                ]}>
                  {Session.device(session)}
                </p>
                <p class="text-xs text-muted">
                  {last_seen(session)} ·
                  <.rich_text text={gettext("signed in %{date}", date: rich_marker("date"))}>
                    <:part name="date">
                      <.local_time id={"session-#{session.id}-signed-in"} value={session.inserted_at} />
                    </:part>
                  </.rich_text>
                </p>
                <p :if={session.ip_address} class="text-xs text-muted">
                  {gettext("IP:")}
                  <span
                    class="relative inline-block font-mono align-baseline cursor-pointer"
                    phx-click={
                      JS.toggle_class("invisible", to: "#ip-mask-#{session.id}")
                      |> JS.toggle_class("opacity-0 pointer-events-none", to: "#ip-val-#{session.id}")
                    }
                  >
                    <span id={"ip-mask-#{session.id}"} class="blur-sm select-none">xxx.xxx.xxx.xxx</span>
                    <span id={"ip-val-#{session.id}"} class="absolute inset-0 opacity-0 pointer-events-none">{session.ip_address}</span>
                  </span>
                </p>
              </div>
              <.sticker :if={session.id == @current_session_id} size="xs" tilt={false} class="shrink-0 uppercase">
                {gettext("This one")}
              </.sticker>
              <.ink_button
                :if={session.id != @current_session_id}
                variant="ghost"
                size="md"
                class="shrink-0"
                phx-click="revoke_session"
                phx-value-id={session.id}
                aria-label={gettext("Sign out %{device}", device: Session.device(session))}
              >
                {gettext("Sign out")}
              </.ink_button>
            </li>
          </ul>
          <p :if={@sessions == []} id="sessions-empty" class="mb-5 text-sm text-faint">
            {gettext("None recorded yet. Sign-ins from before this list existed show up once they sign in again.")}
          </p>
          <p class="mb-5 text-sm text-muted">
            {gettext("Left a device signed in? This signs the account out of every browser and app except this one.")}
          </p>
          <form id="sessions-form" method="post" action={~p"/settings/sessions/revoke"}>
            <input type="hidden" name="_csrf_token" value={@csrf} />
            <.ink_button type="submit" size="md" variant="warning">
              <.icon name="lucide-log-out" class="w-4 h-4" /> {gettext("Sign out everywhere else")}
            </.ink_button>
          </form>
        </.panel>
      </div>
    </div>
    """
  end

  defp about_tab(assigns) do
    assigns =
      assign(assigns,
        version: Application.spec(:stashix, :vsn),
        source_url: Application.fetch_env!(:stashix, :source_url)
      )

    ~H"""
    <.panel variant="indicia">
      <.stat_list class="px-6 py-5">
        <.stat label={gettext("Version")}>{@version}</.stat>
        <.stat label={gettext("License")}>AGPL-3.0-or-later</.stat>
      </.stat_list>
    </.panel>

    <.section title={gettext("Source code")}>
      <p class="max-w-xl -mt-1 text-sm text-muted">
        <.rich_text text={
          gettext(
            "Stashix is free software: you can redistribute and modify it under the terms of the %{license}, version 3 or later. The source code for this server is at %{source}.",
            license: rich_marker("license"),
            source: rich_marker("source")
          )
        }>
          <:part name="license">
            <a
              href="https://www.gnu.org/licenses/agpl-3.0.html"
              target="_blank"
              rel="noopener noreferrer"
              class="underline underline-offset-4 hover:text-fg"
            >{gettext("GNU Affero General Public License")}</a>
          </:part>
          <:part name="source">
            <a
              id="source-link"
              href={@source_url}
              target="_blank"
              rel="noopener noreferrer"
              class="underline underline-offset-4 hover:text-fg"
            >{@source_url}</a>
          </:part>
        </.rich_text>
      </p>
    </.section>
    """
  end
end
