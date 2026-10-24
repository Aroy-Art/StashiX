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

  @doc "True when `path` is `base` or lies under it."
  def under?(nil, _base), do: false
  def under?(path, "/"), do: path == "/"
  def under?(path, base), do: path == base or String.starts_with?(path, base <> "/")
end
