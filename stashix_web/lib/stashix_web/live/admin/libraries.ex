# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.AdminLive.Libraries do
  @moduledoc """
  Libraries tab: add, scan and configure libraries.

  Markup only: `StashixWeb.AdminLive` owns the state and handles every event.
  """
  use StashixWeb, :html

  import StashixWeb.MetadataComponents, only: [needs_sources: 1]

  attr :editing_library_id, :any, required: true
  attr :libraries, :any, required: true
  attr :scanning_libraries, :any, required: true
  attr :show_library_form, :any, required: true
  attr :file_watcher_status, :any, required: true
  attr :sources_ready, :boolean, required: true

  def tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <.display_heading level={1} class="text-4xl!">{gettext("Libraries")}</.display_heading>
        <div class="flex items-center gap-2">
          <.ink_button variant="ghost" size="md" phx-click="backfill_blurhashes">
            {gettext("Backfill Blurhashes")}
          </.ink_button>
          <.ink_button
            size="md"
            phx-click="toggle_library_form"
          >
            {gettext("Add Library")}
          </.ink_button>
        </div>
      </div>

      <div
        :if={match?({:disabled, _}, @file_watcher_status)}
        role="status"
        class="flex gap-3 rounded-lg ring-1 ring-amber-400/40 bg-amber-400/[0.06] p-4"
      >
        <.icon name="lucide-eye-off" class="w-5 h-5 shrink-0 text-warn mt-0.5" />
        <div class="space-y-1 text-sm">
          <p class="font-medium text-warn">{gettext("Live file watching is off")}</p>
          <p class="text-fg-soft">{elem(@file_watcher_status, 1)}</p>
          <p class="text-muted">
            {gettext("New and changed files won't appear on their own. Run Scan on a library to pick them up.")}
          </p>
        </div>
      </div>

      <%= if @show_library_form do %>
        <div class="bg-surface border border-edge rounded-lg p-6">
          <h3 class="font-display font-black uppercase text-2xl leading-none text-fg mb-4">{gettext("Create Library")}</h3>
          <form phx-submit="create_library" class="space-y-4">
            <.field label={gettext("Name")}>
              <.text_input name="name" required placeholder={gettext("My Comics")} />
            </.field>
            <.field label={gettext("Root Path")}>
              <.text_input name="root_path" required placeholder="/libraries/comics" />
            </.field>
            <div class="flex gap-2 justify-end">
              <.ink_button variant="ghost" size="md" type="button" phx-click="toggle_library_form">{gettext("Cancel")}</.ink_button>
              <.ink_button
                size="md"
                type="submit"
              >{gettext("Create")}</.ink_button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="space-y-3">
        <%= for lib <- @libraries do %>
          <div class="bg-surface rounded-lg ring-1 ring-edge overflow-hidden">
            <div class="p-4 flex items-center justify-between">
              <div>
                <p class="text-fg font-medium">{lib.name}</p>
                <p class="text-muted text-sm">{lib.root_path}</p>
                <%= if lib.standalone_folders != [] do %>
                  <p class="text-xs text-muted mt-1">
                    {gettext("Standalone folders: %{folders}", folders: Enum.join(lib.standalone_folders, ", "))}
                  </p>
                <% end %>
              </div>
              <% scanning = MapSet.member?(@scanning_libraries, lib.id) %>
              <div class="flex gap-2 items-center">
                <.ink_button variant="ghost" size="md" phx-click="edit_library" phx-value-id={lib.id}>
                  {gettext("Settings")}
                </.ink_button>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="scan_library"
                  phx-value-id={lib.id}
                  disabled={scanning}
                >
                  <.icon :if={scanning} name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" />
                  {if scanning, do: gettext("Scanning…"), else: gettext("Scan")}
                </.ink_button>
                <.ink_button
                  variant="warning"
                  size="md"
                  phx-click="force_scan_library"
                  phx-value-id={lib.id}
                  disabled={scanning}
                >
                  {gettext("Force rescan")}
                </.ink_button>
                <.needs_sources ready={@sources_ready} class="inline-flex">
                  <.ink_button
                    variant="ghost"
                    size="md"
                    phx-click="match_library_metadata"
                    phx-value-id={lib.id}
                    title={gettext("Look up metadata for unmatched books from the enabled sources")}
                    disabled={!@sources_ready}
                  >
                    {gettext("Match Metadata")}
                  </.ink_button>
                </.needs_sources>
                <.ink_button
                  variant="danger"
                  size="md"
                  phx-click="show_confirm"
                  phx-value-event="delete_library"
                  phx-value-id={lib.id}
                  phx-value-title={gettext("Delete Library")}
                  phx-value-message={
                    gettext(
                      "Delete library \"%{name}\" and ALL its books and series? Book files on disk are never deleted. This cannot be undone.",
                      name: lib.name
                    )
                  }
                  phx-value-label={gettext("Delete")}
                >
                  {gettext("Delete")}
                </.ink_button>
              </div>
            </div>

            <%= if @editing_library_id == lib.id do %>
              <div class="border-t border-fg/10 p-4 bg-canvas">
                <form phx-submit="save_standalone_folders" class="space-y-3">
                  <input type="hidden" name="_id" value={lib.id} />
                  <div>
                    <label class="block mb-1.5 text-[10px] font-bold tracking-[0.18em] uppercase text-fg-soft">
                      {gettext("Standalone folder names")}
                      <span class="text-muted font-normal ml-1">{gettext("(one per line — case insensitive)")}</span>
                    </label>
                    <textarea
                      name="standalone_folders"
                      rows="4"
                      class={input_class()}
                      placeholder={
                        gettext("Default built-in: one-shot, one shot, oneshot\nAdd extras here, e.g.:\nAnnuals\nSpecials")
                      }
                    >{Enum.join(lib.standalone_folders, "\n")}</textarea>
                    <p class="text-xs text-muted mt-1">
                      {gettext("Built-in defaults (always active):")}
                      <span class="text-muted">one-shot, one shot, oneshot</span>
                    </p>
                  </div>
                  <div class="flex gap-2 justify-end">
                    <.ink_button variant="ghost" size="md" type="button" phx-click="cancel_edit_library">{gettext("Cancel")}</.ink_button>
                    <.ink_button
                      size="md"
                      type="submit"
                    >{gettext("Save")}</.ink_button>
                  </div>
                </form>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
