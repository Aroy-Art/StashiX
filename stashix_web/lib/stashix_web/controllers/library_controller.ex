defmodule StashixWeb.LibraryController do
  use StashixWeb, :controller

  alias Stashix.Library

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
