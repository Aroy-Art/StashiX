defmodule StashixWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use StashixWeb, :controller
      use StashixWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.
  """

  def static_paths, do: ~w(assets fonts images icons favicon.ico favicon.png robots.txt manifest.webmanifest sw.js)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: StashixWeb.Layouts]

      use Gettext, backend: StashixWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {StashixWeb.Layouts, :app}

      unquote(html_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: StashixWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML

      # SaladUI components (non-conflicting with CoreComponents)
      import SaladUI.Accordion
      import SaladUI.Alert
      import SaladUI.AlertDialog
      import SaladUI.Avatar
      import SaladUI.Badge
      import SaladUI.Card
      import SaladUI.Checkbox
      import SaladUI.Collapsible
      import SaladUI.Dialog
      import SaladUI.DropdownMenu
      import SaladUI.HoverCard
      import SaladUI.Popover
      import SaladUI.Progress
      import SaladUI.RadioGroup
      import SaladUI.ScrollArea
      import SaladUI.Separator
      import SaladUI.Sheet
      import SaladUI.Skeleton
      import SaladUI.Slider
      import SaladUI.Switch
      import SaladUI.Tabs
      import SaladUI.Toggle
      import SaladUI.ToggleGroup
      import SaladUI.Tooltip

      # Icon component (both lucide- and hero- prefixes)
      import StashixUi.Icon

      # Core UI components (overrides any SaladUI conflicts)
      import StashixWeb.CoreComponents

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: StashixWeb.Endpoint,
        router: StashixWeb.Router,
        statics: StashixWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
