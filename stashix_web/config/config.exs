# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

repo_tmp = Path.expand("../../tmp/data", __DIR__)

config :stashix,
  ecto_repos: [Stashix.Repo],
  generators: [timestamp_type: :utc_datetime],
  data_dir: System.get_env("DATA_DIR") || "/tmp/stashix",
  thumbnail_dir: System.get_env("THUMBNAIL_DIR") || Path.join(repo_tmp, "thumbnails"),
  image_cache_dir: System.get_env("IMAGE_CACHE_DIR") || Path.join(repo_tmp, "cache/images/resized"),
  library_path: System.get_env("LIBRARY_PATH") || "/libraries"

config :stashix, Stashix.Auth.Guardian,
  issuer: "stashix",
  secret_key: System.get_env("JWT_SECRET") || "dev-secret-change-in-production",
  ttl: {15, :minutes}

config :cors_plug,
  origin: ["*"],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]

# Configures the endpoint
config :stashix, StashixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StashixWeb.ErrorHTML, json: StashixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Stashix.PubSub,
  live_view: [signing_salt: "l8B43e3a"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  stashix: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.5",
  stashix: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :mime, :types, %{
  "application/manifest+json" => ["webmanifest"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
