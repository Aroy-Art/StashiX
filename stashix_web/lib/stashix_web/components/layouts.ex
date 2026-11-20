# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use StashixWeb, :controller` and
  `use StashixWeb, :live_view`.
  """
  use StashixWeb, :html

  @dev_routes Application.compile_env(:stashix, :dev_routes, false)
  def dev_routes, do: @dev_routes

  embed_templates "layouts/*"

  @doc """
  The theme for `<html data-theme>` on the first paint. The account's choice is
  stored in `ui_settings`; the browser keeps a copy in the `stashix_theme`
  cookie (written by app.js on every `phx:set-theme`) so the page is drawn in
  the right colours before the LiveView connects, and on the login page.
  """
  def theme_attr(%Plug.Conn{cookies: %{"stashix_theme" => theme}}) when theme in ~w(dark light), do: theme
  def theme_attr(_conn), do: "system"

  @dev_build Mix.env() == :dev

  @doc "The running app version (`dev` in a dev build) and where its source lives, for the sidebar foot."
  def app_version, do: if(@dev_build, do: "dev", else: "v#{Application.spec(:stashix, :vsn)}")
  def source_url, do: Application.fetch_env!(:stashix, :source_url)

  @doc """
  Sidebar link. The current page carries the same ink bar as the active item
  of a menu, with its icon in violet.
  """
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :icon_class, :string, default: nil
  attr :active, :boolean, default: false
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      aria-current={@active && "page"}
      class={[
        "nav-item ink-menu-item group flex items-center gap-3 min-w-0 px-3 py-2 rounded-sm font-display font-bold uppercase tracking-[0.07em] text-lg lg:text-base leading-6 transition-colors",
        if(@active, do: "is-active", else: "text-fg-soft hover:text-fg hover:bg-fg/[0.06]"),
        @class
      ]}
    >
      <.icon
        name={@icon}
        class={"ink-menu-icon w-[18px] h-[18px] shrink-0 #{@icon_class || "text-muted group-hover:text-fg-soft"}"}
      />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  The Comics/Books switcher (`StashixWeb.Live.Hooks.assign_library_kind/1`):
  a menu row styled like the theme menu in the sidebar, or a menu in the
  top bar. Shows only when the user's libraries are of more than one kind.

  The top bar has no room for it below `lg`, so the sidebar drawer then
  carries a sidebar copy whatever the setting. `id` and `item_prefix` keep
  that copy's ids apart from the top bar's.
  """
  attr :kind, :string, required: true
  attr :kinds, :list, required: true
  attr :placement, :string, values: ~w(sidebar top), required: true
  attr :id, :string, default: "kind-switcher"
  attr :item_prefix, :string, default: "kind"
  attr :class, :string, default: nil

  def kind_switcher(%{kinds: kinds} = assigns) when length(kinds) < 2, do: ~H""

  def kind_switcher(%{placement: "sidebar"} = assigns) do
    ~H"""
    <div class={["p-2 border-b border-fg/10", @class]}>
      <.ink_menu id={@id} align="start" class="flex w-full" panel_class="w-44">
        <:trigger
          label={gettext("Show libraries: %{kind}", kind: kind_label(@kind))}
          class="flex items-center gap-3 w-full px-3 py-2 rounded-sm font-display font-bold uppercase tracking-[0.07em] text-sm text-muted hover:text-fg hover:bg-fg/[0.06] transition-colors"
        >
          <.icon name={kind_icon(@kind)} class="w-4 h-4 text-ink" />
          <span class="text-fg-soft">{kind_title(@kind)}</span>
          <.icon name="lucide-chevron-down" class="ml-auto w-3.5 h-3.5 text-faint" />
        </:trigger>
        <.kind_menu_items kind={@kind} kinds={@kinds} item_prefix={@item_prefix} />
      </.ink_menu>
    </div>
    """
  end

  def kind_switcher(assigns) do
    ~H"""
    <.ink_menu id={@id} align="start" panel_class="w-44" class={"shrink-0 #{@class}"}>
      <:trigger
        label={gettext("Show libraries: %{kind}", kind: kind_label(@kind))}
        class="flex items-center gap-1.5 h-9 px-2 sm:px-2.5 rounded-md text-sm text-fg-soft ring-1 ring-fg/15 hover:text-fg hover:bg-fg/10 transition-colors"
      >
        <.icon name={kind_icon(@kind)} class="w-4 h-4 text-ink" />
        <span class="hidden sm:inline font-display font-bold uppercase tracking-[0.07em]">{kind_label(@kind)}</span>
        <.icon name="lucide-chevron-down" class="hidden sm:block w-3.5 h-3.5 text-muted" />
      </:trigger>
      <.kind_menu_items kind={@kind} kinds={@kinds} item_prefix={@item_prefix} />
    </.ink_menu>
    """
  end

  attr :kind, :string, required: true
  attr :kinds, :list, required: true
  attr :item_prefix, :string, required: true

  defp kind_menu_items(assigns) do
    ~H"""
    <.menu_label>{gettext("Show libraries")}</.menu_label>
    <.menu_item
      :for={kind <- ["all" | Enum.map(@kinds, &to_string/1)]}
      id={"#{@item_prefix}-#{kind}"}
      icon={kind_icon(kind)}
      active={@kind == kind}
      phx-click="set_library_kind"
      phx-value-kind={kind}
    >
      {kind_title(kind)}
    </.menu_item>
    """
  end

  defp kind_label("comics"), do: gettext("Comics")
  defp kind_label("books"), do: gettext("Books")
  defp kind_label(_all), do: gettext("All")

  defp kind_title("comics"), do: gettext("Comics & manga")
  defp kind_title("books"), do: gettext("Books")
  defp kind_title(_all), do: gettext("All libraries")

  defp kind_icon("comics"), do: "lucide-book-image"
  defp kind_icon("books"), do: "lucide-book-open-text"
  defp kind_icon(_all), do: "lucide-library"

  @doc "Tag on a navbar quick result."
  def result_type_label(:series), do: gettext("Series")
  def result_type_label(:issue), do: gettext("Issue")
  def result_type_label(:book), do: gettext("Book")

  @doc "True when `path` is `base` or lies under it."
  def under?(nil, _base), do: false
  def under?(path, "/"), do: path == "/"
  def under?(path, base), do: path == base or String.starts_with?(path, base <> "/")
end
