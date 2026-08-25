defmodule StashixWeb.Router do
  use StashixWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StashixWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
  end

  pipeline :media do
    plug CORSPlug
  end

  pipeline :auth do
    plug Stashix.Auth.Pipeline
    plug :require_authenticated
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

  scope "/api", StashixWeb do
    pipe_through :api

    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    get "/setup/status", SetupController, :status
    post "/setup", SetupController, :create
  end

  scope "/api", StashixWeb do
    pipe_through :media

    get "/books/:id/cover", BookController, :cover
    get "/books/:id/page/:n", BookController, :page
  end

  scope "/api", StashixWeb do
    pipe_through [:api, :auth]

    get "/users/profile", UserController, :profile
    get "/tasks", TaskController, :index

    resources "/libraries", LibraryController, only: [:index, :create, :show, :update]
    post "/libraries/:id/scan", LibraryController, :scan
    get "/libraries/:id/books", BookController, :index
    get "/libraries/:id/series", SeriesController, :index

    get "/books/:id", BookController, :show
    get "/books/:id/pages", BookController, :pages
    put "/books/:id/progress", BookController, :progress

    get "/series/:id", SeriesController, :show
    get "/series/:id/cover", SeriesController, :cover

    get "/search", SearchController, :search

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
  end

  scope "/", StashixWeb do
    pipe_through :browser

    live "/", LibrariesLive, :index
    live "/library/:id", LibraryLive, :index
    live "/book/:id", BookLive, :show
    live "/series/:id", SeriesLive, :show
    live "/search", SearchLive, :index
    live "/read/:id", ReaderLive, :show
    live "/admin", AdminLive, :index
  end

  if Application.compile_env(:stashix, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: StashixWeb.Telemetry
    end
  end
end
