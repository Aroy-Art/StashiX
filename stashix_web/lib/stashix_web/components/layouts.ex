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
  Sidebar link. The current page carries the same ink bar as the active item
  of a menu.
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
        "ink-menu-item group flex items-center gap-3 min-w-0 px-3 py-2 rounded-sm font-display font-bold uppercase tracking-wide text-[15px] leading-5 transition-colors",
        if(@active, do: "is-active", else: "text-gray-400 hover:text-white hover:bg-white/[0.05]"),
        @class
      ]}
    >
      <.icon
        name={@icon}
        class={"ink-menu-icon w-4 h-4 shrink-0 #{@icon_class || "text-gray-500 group-hover:text-gray-300"}"}
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
