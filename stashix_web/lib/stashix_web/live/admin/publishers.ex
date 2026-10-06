defmodule StashixWeb.AdminLive.Publishers do
  @moduledoc """
  Publishers tab: link aliases and hide publishers from listings.

  Markup only: `StashixWeb.AdminLive` owns the state and handles every event.
  """
  use StashixWeb, :html

  attr :alias_pending, :any, required: true
  attr :alias_source_id, :any, required: true
  attr :alias_source_query, :any, required: true
  attr :alias_target_id, :any, required: true
  attr :alias_target_query, :any, required: true
  attr :pub_vis_page, :any, required: true
  attr :pub_vis_publishers, :any, required: true
  attr :pub_vis_search, :any, required: true
  attr :pub_vis_stats, :any, required: true
  attr :pub_vis_total, :any, required: true
  attr :publisher_tab, :any, required: true
  attr :publishers, :any, required: true
  attr :publishers_with_aliases, :any, required: true

  def tab(assigns) do
    ~H"""
    <% alias_pub = Enum.find(@publishers, &(&1.id == @alias_source_id))
    master_pub = Enum.find(@publishers, &(&1.id == @alias_target_id)) %>
    <div class="space-y-6">
      <.display_heading level={1} class="text-4xl!">Publishers</.display_heading>

      <%!-- Tab bar --%>
      <.tabs label="Publisher tools">
        <:tab patch={~p"/admin/publishers?tab=aliases"} active={@publisher_tab == "aliases"}>Aliases</:tab>
        <:tab patch={~p"/admin/publishers?tab=visibility"} active={@publisher_tab == "visibility"}>Visibility</:tab>
      </.tabs>

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
                    class="w-full bg-gray-900 border border-white/15 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
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
                      class="absolute z-20 top-full left-0 right-0 mt-1 bg-gray-800 border border-white/15 rounded-lg overflow-hidden shadow-xl"
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
                    class="w-full bg-gray-900 border border-white/15 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500"
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
                      class="absolute z-20 top-full left-0 right-0 mt-1 bg-gray-800 border border-white/15 rounded-lg overflow-hidden shadow-xl"
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
              <.ink_button
                size="md"
                phx-click="preview_alias"
                disabled={is_nil(@alias_source_id) || is_nil(@alias_target_id)}
              >
                Link as Alias
              </.ink_button>
            <% else %>
              <div class="rounded-lg border border-violet-800/60 bg-violet-950/30 p-4 space-y-3">
                <p class="text-sm text-violet-300 font-medium">Confirm alias link</p>
                <p class="text-sm text-gray-400">
                  <span class="text-white font-medium">"{alias_pub && alias_pub.name}"</span>
                  will become an alias of <span class="text-white font-medium">"{master_pub && master_pub.name}"</span>.
                  No data is deleted — this can be undone.
                </p>
                <div class="flex gap-2">
                  <.ink_button
                    size="md"
                    phx-click="confirm_set_alias"
                  >
                    Confirm
                  </.ink_button>
                  <.ink_button variant="ghost" size="md" phx-click="cancel_alias">
                    Cancel
                  </.ink_button>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Current aliases --%>
          <div>
            <h3 class="text-sm font-medium text-gray-400 mb-2">
              Current aliases
              <%= if @publishers_with_aliases != [] do %>
                <span class="text-gray-500">({length(@publishers_with_aliases)})</span>
              <% end %>
            </h3>
            <div class="rounded-lg border border-white/10 overflow-hidden">
              <table class="w-full text-sm">
                <thead>
                  <tr class="border-b border-white/10 bg-gray-900/50">
                    <th class="px-3 py-2 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                      Master
                    </th>
                    <th class="px-3 py-2 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                      Alias
                    </th>
                    <th></th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-white/10">
                  <%= if @publishers_with_aliases == [] do %>
                    <tr>
                      <td colspan="3" class="px-3 py-4 text-center text-sm text-gray-500">
                        No aliases configured
                      </td>
                    </tr>
                  <% else %>
                    <%= for p <- @publishers_with_aliases do %>
                      <tr class="group hover:bg-gray-800/40 transition-colors">
                        <td class="px-3 py-2">
                          <.link
                            navigate={~p"/publisher/#{p.canonical_publisher_id}"}
                            class="text-gray-300 hover:text-violet-300 transition-colors"
                          >
                            {p.canonical && p.canonical.name}
                          </.link>
                        </td>
                        <td class="px-3 py-2">
                          <.link
                            navigate={~p"/publisher/#{p.canonical_publisher_id}"}
                            class="text-gray-400 hover:text-violet-300 transition-colors"
                          >
                            {p.name}
                          </.link>
                        </td>
                        <td class="px-3 py-2 text-right">
                          <.ink_button variant="danger" size="md" phx-click="remove_alias" phx-value-id={p.id}>
                            Remove
                          </.ink_button>
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
                class="w-full bg-gray-900 border border-white/10 rounded-lg pl-9 pr-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-violet-500/70"
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
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="pub_vis_page"
                  phx-value-page={@pub_vis_page - 1}
                  disabled={@pub_vis_page <= 1}
                >‹</.ink_button>
                <%= for pg <- max(1, @pub_vis_page - 2)..min(total_pages, @pub_vis_page + 2) do %>
                  <button
                    phx-click="pub_vis_page"
                    phx-value-page={pg}
                    class={[
                      "px-2.5 py-1 rounded text-sm border transition-colors",
                      if(pg == @pub_vis_page,
                        do: "bg-violet-600 border-violet-500 text-white",
                        else: "bg-gray-800 border-white/15 text-gray-400 hover:bg-gray-700"
                      )
                    ]}
                  >{pg}</button>
                <% end %>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="pub_vis_page"
                  phx-value-page={@pub_vis_page + 1}
                  disabled={@pub_vis_page >= total_pages}
                >›</.ink_button>
              </div>
            <% end %>
          </div>

          <div class="rounded-lg border border-white/10 overflow-hidden">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-white/10 bg-gray-900/50">
                  <th class="px-3 py-2 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Name
                  </th>
                  <th class="px-3 py-2 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Status
                  </th>
                  <th class="px-3 py-2 text-right text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Series
                  </th>
                  <th class="px-3 py-2 text-right text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Books
                  </th>
                  <th class="px-3 py-2 text-right text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                    Issues
                  </th>
                  <th></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/10">
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
                      <.link
                        navigate={~p"/publisher/#{p.id}"}
                        class={"hover:text-violet-300 transition-colors #{if effectively_hidden, do: "text-gray-500 line-through", else: "text-gray-300"}"}
                      >
                        {p.name}
                      </.link>
                    </td>
                    <td class="px-3 py-2">
                      <%= cond do %>
                        <% p.hidden -> %>
                          <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-white/15">Hidden</span>
                        <% master_hidden -> %>
                          <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-white/15">Alias · Hidden</span>
                        <% not is_nil(p.canonical_publisher_id) -> %>
                          <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-gray-800 text-gray-500 border border-white/15">Alias</span>
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
                    <td colspan="6" class="px-3 py-6 text-center text-sm text-gray-500">
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
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="pub_vis_page"
                  phx-value-page={@pub_vis_page - 1}
                  disabled={@pub_vis_page <= 1}
                >‹</.ink_button>
                <%= for pg <- max(1, @pub_vis_page - 2)..min(total_pages, @pub_vis_page + 2) do %>
                  <button
                    phx-click="pub_vis_page"
                    phx-value-page={pg}
                    class={[
                      "px-2.5 py-1 rounded text-sm border transition-colors",
                      if(pg == @pub_vis_page,
                        do: "bg-violet-600 border-violet-500 text-white",
                        else: "bg-gray-800 border-white/15 text-gray-400 hover:bg-gray-700"
                      )
                    ]}
                  >{pg}</button>
                <% end %>
                <.ink_button
                  variant="ghost"
                  size="md"
                  phx-click="pub_vis_page"
                  phx-value-page={@pub_vis_page + 1}
                  disabled={@pub_vis_page >= total_pages}
                >›</.ink_button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
