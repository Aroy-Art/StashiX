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
end
