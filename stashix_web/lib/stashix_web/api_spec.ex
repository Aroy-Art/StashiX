defmodule StashixWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, SecurityScheme, Server}

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [%Server{url: "/"}],
      info: %Info{
        title: "Stashix API",
        version: "1.0.0",
        description: "Comic book library management API"
      },
      paths: OpenApiSpex.Paths.from_router(StashixWeb.Router),
      components: %Components{
        securitySchemes: %{
          "Bearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT access token from /api/auth/login"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
