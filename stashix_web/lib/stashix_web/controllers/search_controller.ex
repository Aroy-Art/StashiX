defmodule StashixWeb.SearchController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias StashixWeb.Schemas

  operation :search,
    summary: "Search books",
    tags: ["Search"],
    security: [%{"Bearer" => []}],
    parameters: [
      q: [in: :query, type: :string, required: true, description: "Search query"],
      limit: [in: :query, type: :integer, description: "Max results (default 50)"],
      offset: [in: :query, type: :integer, description: "Pagination offset"]
    ],
    responses: [
      ok: {"Search results", "application/json", Schemas.SearchResult},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

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
