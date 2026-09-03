defmodule StashixWeb.LibraryController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias StashixWeb.Schemas

  operation :index,
    summary: "List libraries",
    tags: ["Libraries"],
    security: [%{"Bearer" => []}],
    responses: [
      ok: {"Library list", "application/json", %OpenApiSpex.Schema{
        type: :object,
        properties: %{libraries: %OpenApiSpex.Schema{type: :array, items: Schemas.Library}}
      }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    libraries = Library.list_libraries(user)

    data =
      Enum.map(libraries, fn lib ->
        %{
          id: lib.id,
          name: lib.name,
          root_path: lib.root_path,
          book_count: Library.count_books(lib.id),
          series_count: Library.count_series(lib.id),
          inserted_at: lib.inserted_at
        }
      end)

    json(conn, %{libraries: data})
  end

  operation :show,
    summary: "Get library by ID",
    tags: ["Libraries"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok: {"Library details", "application/json", Schemas.LibraryDetail},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    library = Library.get_library!(id)

    json(conn, %{
      id: library.id,
      name: library.name,
      root_path: library.root_path,
      standalone_folders: library.standalone_folders,
      book_count: Library.count_books(library.id),
      series_count: Library.count_series(library.id),
      inserted_at: library.inserted_at
    })
  end

  operation :create,
    summary: "Create library",
    tags: ["Libraries"],
    security: [%{"Bearer" => []}],
    request_body: {"Library params", "application/json", Schemas.LibraryRequest, required: true},
    responses: [
      created: {"Created library", "application/json", %OpenApiSpex.Schema{
        type: :object,
        properties: %{library: Schemas.Library}
      }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def create(conn, params) do
    case Library.create_library(params) do
      {:ok, library} ->
        conn
        |> put_status(:created)
        |> json(%{library: %{id: library.id, name: library.name, root_path: library.root_path}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  operation :update,
    summary: "Update library",
    tags: ["Libraries"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body: {"Library params", "application/json", Schemas.LibraryRequest, required: true},
    responses: [
      ok: {"Updated library", "application/json", %OpenApiSpex.Schema{
        type: :object,
        properties: %{library: Schemas.Library}
      }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def update(conn, %{"id" => id} = params) do
    library = Library.get_library!(id)

    case Library.update_library(library, params) do
      {:ok, updated} ->
        json(conn, %{library: %{id: updated.id, name: updated.name, root_path: updated.root_path}})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  operation :scan,
    summary: "Trigger library scan",
    tags: ["Libraries"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok: {"Scan started", "application/json", %OpenApiSpex.Schema{
        type: :object,
        properties: %{
          status: %OpenApiSpex.Schema{type: :string},
          library_id: %OpenApiSpex.Schema{type: :integer}
        }
      }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def scan(conn, %{"id" => id}) do
    Stashix.Scanner.scan_library(id)
    json(conn, %{status: "scan_started", library_id: id})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
