# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Router do
  use StashixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StashixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug StashixWeb.Locale
    plug StashixWeb.Plugs.CheckSetup
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
    plug OpenApiSpex.Plug.PutApiSpec, module: StashixWeb.ApiSpec
  end

  pipeline :reader_csp do
    plug StashixWeb.Plugs.ReaderCSP
  end

  pipeline :media do
    plug CORSPlug
    plug :fetch_session
    plug StashixWeb.Plugs.MediaAuth
    plug StashixWeb.Plugs.AssignAccess
  end

  pipeline :csrf do
    plug :protect_from_forgery
  end

  pipeline :auth do
    plug Stashix.Auth.Pipeline
    plug :require_authenticated
    plug StashixWeb.Plugs.AssignAccess
  end

  # OPDS clients sign every request with HTTP Basic and an app password.
  pipeline :opds do
    plug StashixWeb.Plugs.OpdsAuth
    plug StashixWeb.Plugs.AssignAccess
  end

  pipeline :admin do
    plug StashixWeb.Plugs.RequireAdmin
  end

  defp require_authenticated(conn, _opts) do
    if Guardian.Plug.current_resource(conn) do
      conn
    else
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, Jason.encode!(%{error: "unauthorized"}))
      |> Plug.Conn.halt()
    end
  end

  scope "/api" do
    pipe_through :api

    get "/schema", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/schema/ui" do
    get "/swagger", OpenApiSpex.Plug.SwaggerUI, path: "/api/schema"
    get "/scalar", ScalarPlug, path: "/api/schema/ui/scalar", spec_href: "/api/schema"
  end

  scope "/api", StashixWeb do
    pipe_through :api

    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    get "/setup/status", SetupController, :status
    post "/setup", SetupController, :create
  end

  scope "/opds/v1.2", StashixWeb do
    pipe_through :opds

    get "/catalog", OpdsController, :root
    get "/libraries", OpdsController, :libraries
    get "/libraries/:id", OpdsController, :library
    get "/series", OpdsController, :series_index
    get "/collections", OpdsController, :collections
    get "/collections/:id", OpdsController, :collection
    get "/series/:id", OpdsController, :series
    get "/books", OpdsController, :books
    get "/new", OpdsController, :new
    get "/continue", OpdsController, :continue
    get "/search", OpdsController, :search
    get "/search.xml", OpdsController, :opensearch

    get "/books/:id/cover", BookController, :cover
    get "/books/:id/page/:n", BookController, :page
    get "/books/:id/download", DownloadController, :book
    get "/books/:id/progression", OpdsController, :progression
    put "/books/:id/progression", OpdsController, :update_progression
  end

  scope "/opds/v2", StashixWeb do
    pipe_through :opds

    get "/catalog", OpdsController, :root
    get "/auth", OpdsController, :authentication
    get "/libraries", OpdsController, :libraries
    get "/libraries/:id", OpdsController, :library
    get "/series", OpdsController, :series_index
    get "/collections", OpdsController, :collections
    get "/collections/:id", OpdsController, :collection
    get "/series/:id", OpdsController, :series
    get "/books", OpdsController, :books
    get "/new", OpdsController, :new
    get "/continue", OpdsController, :continue
    get "/search", OpdsController, :search

    get "/books/:id", OpdsController, :publication
    get "/books/:id/manifest", OpdsController, :manifest
    get "/books/:id/progression", OpdsController, :progression
    put "/books/:id/progression", OpdsController, :update_progression
    get "/books/:id/cover", BookController, :cover
    get "/books/:id/page/:n", BookController, :page
    get "/books/:id/download", DownloadController, :book
  end

  # No :accepts: KOReader asks for application/vnd.koreader.v1+json.
  pipeline :koreader do
    plug StashixWeb.Plugs.KoreaderAuth
    plug StashixWeb.Plugs.AssignAccess
  end

  # KOReader's progress sync (kosync); users are made in Stashix.
  scope "/koreader", StashixWeb do
    post "/users/create", KoreaderController, :create_user
  end

  scope "/koreader", StashixWeb do
    pipe_through :koreader

    get "/users/auth", KoreaderController, :auth
    get "/syncs/progress/:document", KoreaderController, :show
    put "/syncs/progress", KoreaderController, :update
  end

  # A Kobo eReader's store address points here (see KoboController).
  pipeline :kobo do
    plug StashixWeb.Plugs.KoboAuth
    plug StashixWeb.Plugs.AssignAccess
  end

  scope "/kobo/:token", StashixWeb do
    pipe_through :kobo

    get "/v1/initialization", KoboController, :initialization
    post "/v1/auth/device", KoboController, :auth_device
    get "/v1/library/sync", KoboController, :sync
    get "/v1/library/:id/metadata", KoboController, :metadata
    get "/v1/library/:id/state", KoboController, :state
    put "/v1/library/:id/state", KoboController, :update_state
    post "/v1/library/tags", KoboController, :create_tag
    put "/v1/library/tags/:tag_id", KoboController, :update_tag
    delete "/v1/library/tags/:tag_id", KoboController, :update_tag
    post "/v1/library/tags/:tag_id/items", KoboController, :add_tag_items
    post "/v1/library/tags/:tag_id/items/delete", KoboController, :remove_tag_items
    get "/v1/books/:id/file/epub", KoboController, :download
    get "/v1/books/:id/thumbnail/:width/:height/:grey/image.jpg", KoboController, :cover
    get "/v1/books/:id/thumbnail/:width/:height/:quality/:grey/image.jpg", KoboController, :cover
    match :*, "/*path", KoboController, :other
  end

  # Komga's read-progress call, for reading apps that send it as you read.
  scope "/api/v1", StashixWeb do
    pipe_through :opds

    patch "/books/:id/read-progress", OpdsController, :read_progress
  end

  scope "/api", StashixWeb do
    pipe_through :media

    get "/books/:id/cover", BookController, :cover
    get "/books/:id/page/:n", BookController, :page
    get "/books/:id/file", BookFileController, :show
    get "/books/:id/epub", EpubController, :index
    get "/books/:id/epub/*entry", EpubController, :entry
    get "/books/:id/download", DownloadController, :book
    get "/books/:id/annotations/export", AnnotationController, :export
    get "/annotations/:id/preview", AnnotationController, :preview
    get "/series/:id/cover", SeriesController, :cover
    get "/series/:id/download", DownloadController, :series
    get "/collections/:id/download", DownloadController, :collection
    get "/metadata/image", MetadataImageController, :show
  end

  # Posted by a browser form, so it needs the CSRF token.
  scope "/api", StashixWeb do
    pipe_through [:media, :csrf]

    post "/download", DownloadController, :selection
  end

  scope "/api", StashixWeb do
    pipe_through [:api, :auth]

    get "/users/profile", UserController, :profile
    get "/tasks", TaskController, :index

    resources "/libraries", LibraryController, only: [:index, :show]
    get "/libraries/:id/books", BookController, :index
    get "/libraries/:id/series", SeriesController, :index

    get "/books/:id", BookController, :show
    get "/books/:id/pages", BookController, :pages
    get "/books/:id/progress", BookController, :show_progress
    put "/books/:id/progress", BookController, :progress

    get "/series/:id", SeriesController, :show

    get "/creators/:id", CreatorController, :show

    resources "/collections", CollectionController, only: [:index, :show, :create, :update, :delete]
    get "/collections/:id/books", CollectionController, :books
    post "/collections/:id/entries", CollectionController, :add_entry
    delete "/collections/:id/entries/:entry_id", CollectionController, :remove_entry
    put "/collections/:id/entries/:entry_id/position", CollectionController, :move_entry

    get "/search", SearchController, :search

    scope "/" do
      pipe_through :admin

      resources "/libraries", LibraryController, only: [:create, :update]
      post "/libraries/:id/scan", LibraryController, :scan
    end

    scope "/admin" do
      pipe_through :admin

      resources "/users", AdminUserController, only: [:index, :create, :update, :delete]
      post "/users/:id/permissions", AdminUserController, :permissions
    end
  end

  scope "/", StashixWeb do
    pipe_through :browser

    live "/login", LoginLive, :index
    live "/setup", SetupLive, :index

    post "/login", SessionController, :create
    post "/setup", SessionController, :setup
    delete "/logout", SessionController, :delete
  end

  scope "/", StashixWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/library/:id", LibraryLive, :show
    live "/library/:id/series", LibraryLive, :series
    live "/library/:id/books", LibraryLive, :books
    live "/library/:id/issues", LibraryLive, :issues
    live "/books", AllBooksLive, :index
    live "/issues", AllIssuesLive, :index
    live "/series", AllSeriesLive, :index
    live "/collections", CollectionsLive, :index
    live "/collection/:id", CollectionLive, :show
    live "/book/:id", BookLive, :show
    live "/series/:id", SeriesLive, :show
    live "/publishers", AllPublishersLive, :index
    live "/creator/:id", CreatorLive, :show
    live "/publisher/:id", PublisherLive, :show
    live "/publisher/:id/series", PublisherLive, :series
    live "/publisher/:id/books", PublisherLive, :books
    live "/publisher/:id/issues", PublisherLive, :issues
    live "/search", SearchLive, :index
    live "/read/:id", ReaderLive, :show
    live "/admin", AdminLive, :index
    live "/admin/users", AdminLive, :users
    live "/admin/libraries", AdminLive, :libraries
    live "/admin/cleanup", AdminLive, :cleanup
    live "/admin/publishers", AdminLive, :publishers
    live "/admin/health", AdminHealthLive, :health
    live "/admin/metadata", AdminMetadataLive, :metadata_sources
    live "/admin/metadata/settings", AdminMetadataLive, :metadata_settings
    live "/admin/metadata/review", AdminMetadataLive, :metadata_review
    live "/admin/metadata/jobs", AdminMetadataLive, :metadata_jobs
    live "/stats", StatsLive, :index
    live "/settings", SettingsLive, :ui
    live "/settings/personal", SettingsLive, :personal
    live "/settings/security", SettingsLive, :security
    live "/settings/about", SettingsLive, :about

    post "/settings/password", SettingsController, :update_password
    post "/settings/email", SettingsController, :update_email
    post "/settings/sessions/revoke", SettingsController, :revoke_sessions
  end

  # The text reader shows book content under its own CSP (see
  # StashixWeb.Plugs.ReaderCSP). Its own live_session makes every visit a
  # full page load, so that header always applies.
  scope "/", StashixWeb do
    pipe_through [:browser, :reader_csp]

    live_session :text_reader do
      live "/read/:id/text", TextReaderLive, :show
    end
  end

  if Application.compile_env(:stashix, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard",
        metrics: StashixWeb.Telemetry,
        on_mount: [{StashixWeb.Live.Hooks, :admin_only}]

      live "/ui", StashixWeb.Dev.UiLive, :index
    end
  end
end
