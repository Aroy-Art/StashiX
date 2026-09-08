defmodule StashixWeb.SeriesController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias Stashix.Media.ImageResizer
  alias StashixWeb.Schemas

  operation :index,
    summary: "List series in library",
    tags: ["Series"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, description: "Library ID", type: :integer, required: true]],
    responses: [
      ok:
        {"Series list", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{series: %OpenApiSpex.Schema{type: :array, items: Schemas.Series}}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def index(conn, %{"id" => library_id}) do
    series = Library.list_series(library_id)
    json(conn, %{series: Enum.map(series, &series_json/1)})
  end

  operation :show,
    summary: "Get series with books",
    tags: ["Series"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok: {"Series detail", "application/json", Schemas.SeriesDetail},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    series = Library.get_series_with_books(id)

    json(conn, %{
      series: series_json(series),
      books: Enum.map(series.books, &book_summary/1)
    })
  end

  operation :cover,
    summary: "Get series cover image",
    tags: ["Series", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      w: [in: :query, type: :integer, description: "Resize to width in px"]
    ],
    responses: [
      ok: {"Cover image", "image/jpeg", %OpenApiSpex.Schema{type: :string, format: :binary}},
      not_found: {"No cover", "application/json", Schemas.Error}
    ]

  def cover(conn, %{"id" => id} = params) do
    case Library.get_series_cover(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no cover"})

      path ->
        if File.exists?(path) do
          serve_image(conn, path, params["w"])
        else
          conn |> put_status(:not_found) |> json(%{error: "cover file missing"})
        end
    end
  end

  defp serve_image(conn, path, w) when is_binary(w) do
    case Integer.parse(w) do
      {width, _} when width > 0 -> serve_resized(conn, path, width)
      _ -> serve_image(conn, path, nil)
    end
  end

  defp serve_image(conn, path, _w) do
    conn
    |> put_resp_content_type(MIME.from_path(path))
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_file(200, path)
  end

  defp serve_resized(conn, path, width) do
    format = if webp_supported?(conn), do: :webp, else: :jpeg
    content_type = if format == :webp, do: "image/webp", else: "image/jpeg"

    case ImageResizer.resize(path, width, format) do
      {:ok, resized_path} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_header("vary", "Accept")
        |> send_file(200, resized_path)

      {:error, _} ->
        serve_image(conn, path, nil)
    end
  end

  defp webp_supported?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "image/webp"))
  end

  defp series_json(series) do
    %{
      id: series.id,
      name: series.name,
      sort_name: series.sort_name,
      volume: series.volume,
      language: series.language,
      format: series.format,
      issue_count: series.issue_count,
      ongoing: series.ongoing,
      adult: series.adult,
      library_id: series.library_id,
      inserted_at: series.inserted_at
    }
  end

  defp book_summary(book) do
    %{
      id: book.id,
      title: book.title,
      issue_number: book.issue_number,
      volume: book.volume,
      format: book.format,
      page_count: book.page_count
    }
  end
end
