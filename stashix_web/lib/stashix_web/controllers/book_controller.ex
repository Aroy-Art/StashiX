defmodule StashixWeb.BookController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias Stashix.Media.Extractor
  alias Stashix.Media.ImageResizer
  alias StashixWeb.Schemas

  operation :index,
    summary: "List books in library",
    tags: ["Books"],
    security: [%{"Bearer" => []}],
    parameters: [
      id: [in: :path, description: "Library ID", type: :integer, required: true],
      limit: [in: :query, type: :integer, description: "Max results (default 50)"],
      offset: [in: :query, type: :integer, description: "Pagination offset"],
      sort: [in: :query, type: :string, description: "Sort field"],
      type: [in: :query, type: :string, description: "Filter by book type"]
    ],
    responses: [
      ok:
        {"Book list", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{books: %OpenApiSpex.Schema{type: :array, items: Schemas.Book}}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def index(conn, %{"id" => library_id} = params) do
    opts = [
      limit: parse_int(params["limit"], 50),
      offset: parse_int(params["offset"], 0),
      sort: String.to_atom(params["sort"] || "inserted_at"),
      type: params["type"]
    ]

    books = Library.list_books(library_id, opts)
    json(conn, %{books: Enum.map(books, &book_json/1)})
  end

  operation :show,
    summary: "Get book by ID",
    tags: ["Books"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok:
        {"Book detail", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{book: Schemas.Book}
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    book = Library.get_book_with_series(id)
    json(conn, %{book: book_json(book)})
  end

  operation :pages,
    summary: "List page filenames for book",
    tags: ["Books"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok: {"Page list", "application/json", Schemas.PagesResponse},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error},
      unprocessable_entity: {"Extract error", "application/json", Schemas.Error}
    ]

  def pages(conn, %{"id" => id}) do
    book = Library.get_book!(id)

    case Extractor.list_pages(book.path) do
      {:ok, pages} ->
        json(conn, %{pages: pages, count: length(pages)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  operation :page,
    summary: "Get raw page image",
    tags: ["Books", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      n: [in: :path, type: :integer, required: true, description: "0-based page index"]
    ],
    responses: [
      ok: {"Page image binary", "image/jpeg", %OpenApiSpex.Schema{type: :string, format: :binary}},
      not_found: {"Page not found", "application/json", Schemas.Error}
    ]

  def page(conn, %{"id" => id, "n" => n}) do
    book = Library.get_book!(id)
    page_index = String.to_integer(n)

    case Extractor.get_page(book.path, page_index) do
      {:ok, data} ->
        content_type = detect_image_type(data)

        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, data)

      {:error, :page_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "page not found"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  operation :cover,
    summary: "Get book cover image",
    tags: ["Books", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      w: [in: :query, type: :integer, description: "Resize to width in px"]
    ],
    responses: [
      ok: {"Cover image", "image/jpeg", %OpenApiSpex.Schema{type: :string, format: :binary}},
      not_found: {"No cover", "application/json", Schemas.Error}
    ]

  def cover(conn, %{"id" => id} = params) do
    book = Library.get_book!(id) |> Stashix.Repo.preload(:cover)

    case book.cover do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no cover"})

      cover ->
        if File.exists?(cover.path) do
          serve_image(conn, cover.path, params["w"])
        else
          conn |> put_status(:not_found) |> json(%{error: "cover file missing"})
        end
    end
  end

  operation :progress,
    summary: "Update reading progress",
    tags: ["Books"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :integer, required: true]],
    request_body: {"Progress", "application/json", Schemas.ProgressRequest, required: true},
    responses: [
      ok:
        {"Progress saved", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             status: %OpenApiSpex.Schema{type: :string},
             page: %OpenApiSpex.Schema{type: :integer}
           }
         }},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def progress(conn, %{"id" => id} = params) do
    user = Guardian.Plug.current_resource(conn)
    page = parse_int(params["page"], 0)

    case Library.update_progress(user.id, id, page) do
      {:ok, _} ->
        json(conn, %{status: "ok", page: page})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
    end
  end

  defp book_json(book) do
    %{
      id: book.id,
      title: book.title,
      path: book.path,
      format: book.format,
      issue_number: book.issue_number,
      volume: book.volume,
      year: book.year,
      page_count: book.page_count,
      language: book.language,
      summary: book.summary,
      age_rating: book.age_rating,
      type: book.type,
      file_size: book.file_size,
      series_id: book.series_id,
      library_id: book.library_id,
      has_cover: not is_nil(Map.get(book, :cover)),
      inserted_at: book.inserted_at
    }
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

  defp detect_image_type(<<0xFF, 0xD8, _::binary>>), do: "image/jpeg"
  defp detect_image_type(<<0x89, 0x50, 0x4E, 0x47, _::binary>>), do: "image/png"
  defp detect_image_type(<<"GIF", _::binary>>), do: "image/gif"
  defp detect_image_type(<<"RIFF", _::32, "WEBP", _::binary>>), do: "image/webp"
  defp detect_image_type(_), do: "image/jpeg"

  defp parse_int(nil, default), do: default

  defp parse_int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_int(n, _default) when is_integer(n), do: n
end
