# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CollectionController do
  @moduledoc """
  The REST API for collections (`Stashix.Collections`): the caller's own and
  the shared ones they can see, read-only unless they own them. Books and
  counts are limited to what the caller may read; a series entry stands for
  its books.
  """
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Collections
  alias Stashix.Library.Collection
  alias StashixWeb.Schemas

  @sorts Collection.sorts()

  # The API pipeline signs in with Guardian; collections are per user.
  plug :assign_current_user

  defp assign_current_user(conn, _opts),
    do: assign(conn, :current_user, conn.assigns[:current_user] || Guardian.Plug.current_resource(conn))

  tags ["Collections"]
  security [%{"Bearer" => []}]

  operation :index,
    summary: "List collections",
    description: "The caller's collections and the shared ones holding something they may read.",
    responses: [
      ok:
        {"Collections", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{collections: %OpenApiSpex.Schema{type: :array, items: Schemas.Collection}}
         }}
    ]

  def index(conn, _params) do
    %{current_user: user, access: access} = conn.assigns
    json(conn, %{collections: Enum.map(Collections.list_for(user, access), &collection_json/1)})
  end

  operation :show,
    summary: "Get a collection with its entries",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Collection", "application/json", Schemas.CollectionDetail},
      not_found: {"Not found", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    with {:ok, c} <- fetch(conn, id) do
      json(conn, %{
        collection: summary_json(conn, c),
        entries: conn.assigns.access |> Collections.entries(c) |> Enum.map(&entry_json/1)
      })
    end
  end

  operation :books,
    summary: "List a collection's books",
    description: "Series opened up to their books, without duplicates; `position` is the collection's own order.",
    parameters: [
      id: [in: :path, type: :string, required: true],
      sort: [in: :query, type: :string, description: "position (default), title, year or added"],
      limit: [in: :query, type: :integer, description: "Max results (default 50)"],
      offset: [in: :query, type: :integer]
    ],
    responses: [
      ok:
        {"Books", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{
             books: %OpenApiSpex.Schema{type: :array, items: Schemas.BookSummary},
             total: %OpenApiSpex.Schema{type: :integer}
           }
         }},
      not_found: {"Not found", "application/json", Schemas.Error}
    ]

  def books(conn, %{"id" => id} = params) do
    with {:ok, c} <- fetch(conn, id) do
      sort = if params["sort"] in @sorts, do: params["sort"], else: "position"
      opts = [limit: int(params["limit"], 50) |> min(500), offset: int(params["offset"], 0)]
      {books, total} = Collections.books(conn.assigns.access, c, sort, opts)
      json(conn, %{books: Enum.map(books, &book_json/1), total: total})
    end
  end

  operation :create,
    summary: "Make a collection",
    request_body: {"Collection", "application/json", Schemas.CollectionRequest},
    responses: [
      created: {"Collection", "application/json", Schemas.CollectionDetail},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def create(conn, params) do
    case Collections.create(conn.assigns.current_user, collection_params(params)) do
      {:ok, c} ->
        c = Stashix.Repo.preload(c, :user)
        conn |> put_status(:created) |> json(%{collection: summary_json(conn, c), entries: []})

      {:error, changeset} ->
        validation_error(conn, changeset)
    end
  end

  operation :update,
    summary: "Change a collection",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Collection", "application/json", Schemas.CollectionRequest},
    responses: [
      ok: {"Collection", "application/json", Schemas.Collection},
      forbidden: {"Not the owner", "application/json", Schemas.Error},
      not_found: {"Not found", "application/json", Schemas.Error},
      unprocessable_entity: {"Validation errors", "application/json", Schemas.ValidationErrors}
    ]

  def update(conn, %{"id" => id} = params) do
    with {:ok, c} <- fetch(conn, id) do
      with {:ok, c} <- Collections.update(conn.assigns.current_user, c, collection_params(params)),
           {:ok, c} <- maybe_set_cover(conn, c, params) do
        json(conn, summary_json(conn, Stashix.Repo.preload(c, :user, force: true)))
      else
        {:error, :not_found} ->
          conn |> put_status(:unprocessable_entity) |> json(%{errors: %{cover_book_id: ["no such book"]}})

        {:error, :forbidden} ->
          forbidden(conn)

        {:error, changeset} ->
          validation_error(conn, changeset)
      end
    end
  end

  operation :delete,
    summary: "Delete a collection",
    description: "The books and series stay.",
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      no_content: "Deleted",
      forbidden: {"Not the owner", "application/json", Schemas.Error},
      not_found: {"Not found", "application/json", Schemas.Error}
    ]

  def delete(conn, %{"id" => id}) do
    with {:ok, c} <- fetch(conn, id) do
      case Collections.delete(conn.assigns.current_user, c) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, :forbidden} -> forbidden(conn)
      end
    end
  end

  operation :add_entry,
    summary: "Add a book or a whole series",
    description: "At the end. 201 when added, 200 when it was already there.",
    parameters: [id: [in: :path, type: :string, required: true]],
    request_body: {"Entry", "application/json", Schemas.CollectionEntryRequest},
    responses: [
      created: {"Added", "application/json", Schemas.CollectionEntry},
      ok: {"Already there", "application/json", Schemas.Error},
      bad_request: {"Neither book_id nor series_id", "application/json", Schemas.Error},
      forbidden: {"Not the owner", "application/json", Schemas.Error},
      not_found: {"Collection, book or series not found", "application/json", Schemas.Error}
    ]

  def add_entry(conn, %{"id" => id} = params) do
    with {:ok, c} <- fetch(conn, id),
         {:ok, item} <- item(params) do
      %{current_user: user, access: access} = conn.assigns

      case Collections.add(user, access, c, item) do
        {:ok, :exists} -> json(conn, %{status: "exists"})
        {:ok, entry} -> conn |> put_status(:created) |> json(entry_json(load_entry(access, c, entry.id)))
        {:error, :forbidden} -> forbidden(conn)
        {:error, :not_found} -> not_found(conn)
      end
    else
      {:error, :bad_request} -> conn |> put_status(:bad_request) |> json(%{error: "give book_id or series_id"})
      %Plug.Conn{} = conn -> conn
    end
  end

  operation :remove_entry,
    summary: "Remove an entry",
    parameters: [
      id: [in: :path, type: :string, required: true],
      entry_id: [in: :path, type: :string, required: true]
    ],
    responses: [no_content: "Removed", forbidden: {"Not the owner", "application/json", Schemas.Error}]

  def remove_entry(conn, %{"id" => id, "entry_id" => entry_id}) do
    with {:ok, c} <- fetch(conn, id) do
      case Collections.remove_entry(conn.assigns.current_user, c, entry_id) do
        :ok -> send_resp(conn, :no_content, "")
        {:error, :forbidden} -> forbidden(conn)
        _ -> not_found(conn)
      end
    end
  end

  operation :move_entry,
    summary: "Move an entry",
    parameters: [
      id: [in: :path, type: :string, required: true],
      entry_id: [in: :path, type: :string, required: true]
    ],
    request_body: {"New place", "application/json", Schemas.CollectionMoveRequest},
    responses: [
      no_content: "Moved",
      bad_request: {"No index", "application/json", Schemas.Error},
      forbidden: {"Not the owner", "application/json", Schemas.Error},
      not_found: {"Not found", "application/json", Schemas.Error}
    ]

  def move_entry(conn, %{"id" => id, "entry_id" => entry_id} = params) do
    with {:ok, c} <- fetch(conn, id) do
      case {params["index"], Collections.owner?(c, conn.assigns.current_user)} do
        {index, true} when is_integer(index) and index >= 0 ->
          case Collections.move(conn.assigns.current_user, c, entry_id, index) do
            :ok -> send_resp(conn, :no_content, "")
            _ -> not_found(conn)
          end

        {_, false} ->
          forbidden(conn)

        _ ->
          conn |> put_status(:bad_request) |> json(%{error: "index must be a whole number from 0"})
      end
    end
  end

  ## Helpers

  defp fetch(conn, id) do
    case Collections.get(conn.assigns.current_user, conn.assigns.access, id) do
      {:ok, c} -> {:ok, c}
      {:error, :not_found} -> not_found(conn)
    end
  end

  defp item(%{"book_id" => id}) when is_binary(id), do: uuid_item(:book, id)
  defp item(%{"series_id" => id}) when is_binary(id), do: uuid_item(:series, id)
  defp item(_params), do: {:error, :bad_request}

  defp uuid_item(kind, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, {kind, id}}
      :error -> {:error, :bad_request}
    end
  end

  defp load_entry(access, c, entry_id), do: access |> Collections.entries(c) |> Enum.find(&(&1.id == entry_id))

  defp maybe_set_cover(conn, c, %{"cover_book_id" => id}) do
    %{current_user: user, access: access} = conn.assigns

    case id && Ecto.UUID.cast(id) do
      nil -> Collections.set_cover(user, access, c, nil)
      {:ok, id} -> Collections.set_cover(user, access, c, {:book, id})
      :error -> {:error, :not_found}
    end
  end

  defp maybe_set_cover(_conn, c, _params), do: {:ok, c}

  defp collection_params(params), do: Map.take(params, ~w(name description shared default_sort))

  defp collection_json(%{collection: c, own?: own?, count: count, cover_ids: cover_ids}) do
    %{
      id: c.id,
      name: c.name,
      description: c.description,
      shared: c.shared,
      own: own?,
      owner: c.user.username,
      default_sort: c.default_sort,
      book_count: count,
      cover_book_id: if(c.cover_book_id in cover_ids, do: c.cover_book_id),
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp summary_json(conn, c) do
    ids = [c.id] |> Collections.expanded_ids(conn.assigns.access) |> Map.get(c.id, [])

    collection_json(%{
      collection: c,
      own?: Collections.owner?(c, conn.assigns.current_user),
      count: length(ids),
      cover_ids: ids
    })
  end

  defp entry_json(entry) do
    %{
      id: entry.id,
      type: if(entry.book_id, do: "book", else: "series"),
      position: entry.position,
      book: entry.book && book_json(entry.book),
      series: entry.series && series_json(entry.series)
    }
  end

  defp book_json(book) do
    %{
      id: book.id,
      title: book.title,
      issue_number: book.issue_number,
      volume: book.volume,
      page_count: book.page_count,
      series_id: book.series_id
    }
  end

  defp series_json(series) do
    %{
      id: series.id,
      name: series.name,
      issue_count: series.issue_count,
      ongoing: series.ongoing,
      adult: series.adult,
      library_id: series.library_id
    }
  end

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not found"})

  defp forbidden(conn),
    do: conn |> put_status(:forbidden) |> json(%{error: "only the owner can change this collection"})

  defp validation_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end
end
