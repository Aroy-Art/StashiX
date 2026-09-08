defmodule StashixWeb.Schemas do
  alias OpenApiSpex.Schema

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{type: :string}
      }
    })
  end

  defmodule ValidationErrors do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ValidationErrors",
      type: :object,
      properties: %{
        errors: %Schema{type: :object, additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}}
      }
    })
  end

  defmodule User do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "User",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        email: %Schema{type: :string, format: :email},
        username: %Schema{type: :string},
        display_name: %Schema{type: :string, nullable: true},
        role: %Schema{type: :string, enum: ["admin", "user"]},
        birth_date: %Schema{type: :string, format: :date, nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :email, :username, :role]
    })
  end

  defmodule LoginRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LoginRequest",
      type: :object,
      properties: %{
        login: %Schema{type: :string, description: "Email address or username"},
        password: %Schema{type: :string, format: :password}
      },
      required: [:login, :password]
    })
  end

  defmodule RefreshRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RefreshRequest",
      type: :object,
      properties: %{
        refresh_token: %Schema{type: :string}
      },
      required: [:refresh_token]
    })
  end

  defmodule AuthResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AuthResponse",
      type: :object,
      properties: %{
        access_token: %Schema{type: :string},
        refresh_token: %Schema{type: :string},
        user: StashixWeb.Schemas.User
      },
      required: [:access_token, :refresh_token, :user]
    })
  end

  defmodule SetupStatusResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SetupStatusResponse",
      type: :object,
      properties: %{
        needs_setup: %Schema{type: :boolean}
      },
      required: [:needs_setup]
    })
  end

  defmodule SetupRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SetupRequest",
      type: :object,
      properties: %{
        email: %Schema{type: :string, format: :email},
        username: %Schema{type: :string},
        password: %Schema{type: :string, format: :password}
      },
      required: [:email, :username, :password]
    })
  end

  defmodule Library do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Library",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        root_path: %Schema{type: :string},
        book_count: %Schema{type: :integer},
        series_count: %Schema{type: :integer},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :root_path]
    })
  end

  defmodule LibraryDetail do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LibraryDetail",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        root_path: %Schema{type: :string},
        standalone_folders: %Schema{type: :boolean},
        book_count: %Schema{type: :integer},
        series_count: %Schema{type: :integer},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :root_path]
    })
  end

  defmodule LibraryRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LibraryRequest",
      type: :object,
      properties: %{
        name: %Schema{type: :string},
        root_path: %Schema{type: :string},
        standalone_folders: %Schema{type: :boolean}
      },
      required: [:name, :root_path]
    })
  end

  defmodule Book do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Book",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string},
        path: %Schema{type: :string},
        format: %Schema{type: :string, enum: ["cbz", "cbr", "pdf", "epub"]},
        issue_number: %Schema{type: :number, nullable: true},
        volume: %Schema{type: :integer, nullable: true},
        year: %Schema{type: :integer, nullable: true},
        page_count: %Schema{type: :integer, nullable: true},
        language: %Schema{type: :string, nullable: true},
        summary: %Schema{type: :string, nullable: true},
        age_rating: %Schema{type: :string, nullable: true},
        type: %Schema{type: :string, nullable: true},
        file_size: %Schema{type: :integer, nullable: true},
        series_id: %Schema{type: :string, format: :uuid, nullable: true},
        library_id: %Schema{type: :string, format: :uuid},
        has_cover: %Schema{type: :boolean},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :title, :format, :library_id]
    })
  end

  defmodule BookSummary do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "BookSummary",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string},
        issue_number: %Schema{type: :number, nullable: true},
        volume: %Schema{type: :integer, nullable: true},
        format: %Schema{type: :string},
        page_count: %Schema{type: :integer, nullable: true}
      },
      required: [:id, :title, :format]
    })
  end

  defmodule Series do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Series",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        sort_name: %Schema{type: :string, nullable: true},
        volume: %Schema{type: :integer, nullable: true},
        language: %Schema{type: :string, nullable: true},
        format: %Schema{type: :string, nullable: true},
        issue_count: %Schema{type: :integer, nullable: true},
        ongoing: %Schema{type: :boolean, nullable: true},
        adult: %Schema{type: :boolean},
        library_id: %Schema{type: :string, format: :uuid},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :library_id]
    })
  end

  defmodule SeriesDetail do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SeriesDetail",
      type: :object,
      properties: %{
        series: StashixWeb.Schemas.Series,
        books: %Schema{type: :array, items: StashixWeb.Schemas.BookSummary}
      },
      required: [:series, :books]
    })
  end

  defmodule Task do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Task",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        type: %Schema{type: :string},
        status: %Schema{type: :string},
        library_id: %Schema{type: :string, format: :uuid, nullable: true},
        started_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    })
  end

  defmodule SearchResult do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SearchResult",
      type: :object,
      properties: %{
        query: %Schema{type: :string},
        count: %Schema{type: :integer},
        results: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              title: %Schema{type: :string},
              format: %Schema{type: :string},
              issue_number: %Schema{type: :number, nullable: true},
              series_id: %Schema{type: :string, format: :uuid, nullable: true},
              library_id: %Schema{type: :string, format: :uuid},
              year: %Schema{type: :integer, nullable: true}
            }
          }
        }
      },
      required: [:query, :count, :results]
    })
  end

  defmodule PagesResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PagesResponse",
      type: :object,
      properties: %{
        pages: %Schema{type: :array, items: %Schema{type: :string}},
        count: %Schema{type: :integer}
      },
      required: [:pages, :count]
    })
  end

  defmodule ProgressRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ProgressRequest",
      type: :object,
      properties: %{
        page: %Schema{type: :integer, minimum: 0}
      },
      required: [:page]
    })
  end

  defmodule PermissionsRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PermissionsRequest",
      type: :object,
      properties: %{
        library_id: %Schema{type: :string, format: :uuid},
        can_read: %Schema{type: :boolean},
        max_age_rating: %Schema{type: :string, nullable: true}
      }
    })
  end
end
