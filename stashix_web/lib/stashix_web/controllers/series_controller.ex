defmodule StashixWeb.SeriesController do
  use StashixWeb, :controller

  alias Stashix.Library
  alias Stashix.Media.ImageResizer

  def index(conn, %{"id" => library_id}) do
    series = Library.list_series(library_id)
    json(conn, %{series: Enum.map(series, &series_json/1)})
  end

  def show(conn, %{"id" => id}) do
    series = Library.get_series_with_books(id)

    json(conn, %{
      series: series_json(series),
      books: Enum.map(series.books, &book_summary/1)
    })
  end

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
      {width, _} when width > 0 ->
        case ImageResizer.resize(path, width) do
          {:ok, resized_path} ->
            conn
            |> put_resp_header("cache-control", "public, max-age=86400")
            |> send_file(200, resized_path)

          {:error, _} ->
            conn
            |> put_resp_header("cache-control", "public, max-age=86400")
            |> send_file(200, path)
        end

      _ ->
        serve_image(conn, path, nil)
    end
  end

  defp serve_image(conn, path, _w) do
    conn
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_file(200, path)
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
      publisher_id: series.publisher_id,
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
