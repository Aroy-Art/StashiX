defmodule StashixWeb.SearchController do
  use StashixWeb, :controller

  alias Stashix.Library

  def search(conn, %{"q" => query} = params) do
    opts = [
      limit: parse_int(params["limit"], 50),
      offset: parse_int(params["offset"], 0)
    ]

    books = Library.search_books(query, opts)

    json(conn, %{
      query: query,
      results: Enum.map(books, &book_json/1),
      count: length(books)
    })
  end

  def search(conn, _params) do
    json(conn, %{query: "", results: [], count: 0})
  end

  defp book_json(book) do
    %{
      id: book.id,
      title: book.title,
      format: book.format,
      issue_number: book.issue_number,
      series_id: book.series_id,
      library_id: book.library_id,
      year: book.year
    }
  end

  defp parse_int(nil, default), do: default

  defp parse_int(s, default) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end
end
