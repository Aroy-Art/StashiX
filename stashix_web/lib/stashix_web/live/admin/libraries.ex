defmodule StashixWeb.AdminLive.Libraries do
  @moduledoc """
  Libraries tab: add, scan and configure libraries.

  Markup only: `StashixWeb.AdminLive` owns the state and handles every event.
  """
  use StashixWeb, :html

  attr :editing_library_id, :any, required: true
  attr :libraries, :any, required: true
  attr :scanning_libraries, :any, required: true
  attr :show_library_form, :any, required: true

  def tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <.display_heading level={1} class="text-4xl!">Libraries</.display_heading>
        <div class="flex items-center gap-2">
          <.ink_button variant="ghost" size="md" phx-click="backfill_blurhashes">
            Backfill Blurhashes
          </.ink_button>
          <.ink_button
            size="md"
            phx-click="toggle_library_form"
          >
            Add Library
          </.ink_button>
        </div>
      </div>

      <%= if @show_library_form do %>
        <div class="bg-gray-900 border border-white/15 rounded-lg p-6">
          <h3 class="font-display font-black uppercase text-2xl leading-none text-white mb-4">Create Library</h3>
          <form phx-submit="create_library" class="space-y-4">
            <.field label="Name">
              <.text_input name="name" required placeholder="My Comics" />
            </.field>
            <.field label="Root Path">
              <.text_input name="root_path" required placeholder="/libraries/comics" />
            </.field>
            <div class="flex gap-2 justify-end">
              <.ink_button variant="ghost" size="md" type="button" phx-click="toggle_library_form">Cancel</.ink_button>
              <.ink_button
                size="md"
                type="submit"
              >Create</.ink_button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="space-y-3">
        <%= for lib <- @libraries do %>
          <div class="bg-gray-900 rounded-lg ring-1 ring-white/10 overflow-hidden">
            <div class="p-4 flex items-center justify-between">
              <div>
                <p class="text-white font-medium">{lib.name}</p>
                <p class="text-gray-400 text-sm">{lib.root_path}</p>
                <%= if lib.standalone_folders != [] do %>
                  <p class="text-xs text-gray-400 mt-1">
                    Standalone folders: {Enum.join(lib.standalone_folders, ", ")}
                  </p>
                <% end %>
              </div>
              <% scanning = MapSet.member?(@scanning_libraries, lib.id) %>
              <div class="flex gap-2 items-center">
                <.ink_button variant="ghost" size="md" phx-click="edit_library" phx-value-id={lib.id}>
                  Settings
                </.ink_button>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="scan_library"
                  phx-value-id={lib.id}
                  disabled={scanning}
                >
                  <.icon :if={scanning} name="lucide-loader-circle" class="w-3.5 h-3.5 animate-spin" />
                  {if scanning, do: "Scanning…", else: "Scan"}
                </.ink_button>
                <.ink_button
                  variant="warning"
                  size="md"
                  phx-click="force_scan_library"
                  phx-value-id={lib.id}
                  disabled={scanning}
                >
                  Force rescan
                </.ink_button>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="match_library_metadata"
                  phx-value-id={lib.id}
                  title="Look up metadata for unmatched books from the enabled sources"
                >
                  Match Metadata
                </.ink_button>
                <.ink_button
                  variant="danger"
                  size="md"
                  phx-click="show_confirm"
                  phx-value-event="delete_library"
                  phx-value-id={lib.id}
                  phx-value-title="Delete Library"
                  phx-value-message={"Delete library \"#{lib.name}\" and ALL its books and series? Book files on disk are never deleted. This cannot be undone."}
                  phx-value-label="Delete"
                >
                  Delete
                </.ink_button>
              </div>
            </div>

            <%= if @editing_library_id == lib.id do %>
              <div class="border-t border-white/10 p-4 bg-gray-950">
                <form phx-submit="save_standalone_folders" class="space-y-3">
                  <input type="hidden" name="_id" value={lib.id} />
                  <div>
                    <label class="block mb-1.5 text-[10px] font-bold tracking-[0.18em] uppercase text-gray-300">
                      Standalone folder names
                      <span class="text-gray-400 font-normal ml-1">(one per line — case insensitive)</span>
                    </label>
                    <textarea
                      name="standalone_folders"
                      rows="4"
                      class={input_class()}
                      placeholder="Default built-in: one-shot, one shot, oneshot\nAdd extras here, e.g.:\nAnnuals\nSpecials"
                    >{Enum.join(lib.standalone_folders, "\n")}</textarea>
                    <p class="text-xs text-gray-400 mt-1">
                      Built-in defaults (always active): <span class="text-gray-400">one-shot, one shot, oneshot</span>
                    </p>
                  </div>
                  <div class="flex gap-2 justify-end">
                    <.ink_button variant="ghost" size="md" type="button" phx-click="cancel_edit_library">Cancel</.ink_button>
                    <.ink_button
                      size="md"
                      type="submit"
                    >Save</.ink_button>
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
