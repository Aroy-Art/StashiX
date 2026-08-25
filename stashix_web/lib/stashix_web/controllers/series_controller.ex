defmodule StashixWeb.SeriesController do
  use StashixWeb, :controller

  alias Stashix.Library

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

  def cover(conn, %{"id" => id}) do
    case Library.get_series_cover(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "no cover"})

      path ->
        if File.exists?(path) do
          send_file(conn, 200, path)
        else
          conn |> put_status(:not_found) |> json(%{error: "cover file missing"})
        end
    end
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
