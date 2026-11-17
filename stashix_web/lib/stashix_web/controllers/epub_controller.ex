# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.EpubController do
  @moduledoc """
  Serves a text EPUB to the text reader one entry at a time, so a book is
  never downloaded whole (see `Stashix.Media.Epub`).

  Like `StashixWeb.BookFileController`, only books that open in the text
  reader are served. Entries are the book's own HTML, CSS and fonts and
  must be treated as untrusted: the reader renders them under its page CSP,
  and each response here also forbids scripts and sniffing, in case one is
  opened directly.
  """
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias Stashix.Media.Epub
  alias StashixWeb.Schemas

  # Opened directly, an entry renders sandboxed: no scripts, no requests.
  @entry_csp "sandbox; default-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; font-src 'self'"

  operation :index,
    summary: "List a text EPUB's entries",
    description: "Every zip entry with its uncompressed size. Only for books that open in the text reader.",
    tags: ["Books", "Media"],
    parameters: [id: [in: :path, type: :integer, required: true]],
    responses: [
      ok: {"Entries", "application/json", %OpenApiSpex.Schema{type: :object}},
      forbidden: {"Not a text book", "application/json", Schemas.Error},
      not_found: {"No EPUB", "application/json", Schemas.Error}
    ]

  def index(conn, %{"id" => id}) do
    with {:ok, file} <- epub_file(conn, id),
         {:ok, entries} <- Epub.entries(file.path) do
      conn
      |> put_resp_header("cache-control", "private, no-cache")
      |> json(%{entries: entries})
    else
      error -> fail(conn, error)
    end
  end

  operation :entry,
    summary: "Get one entry of a text EPUB",
    tags: ["Books", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      entry: [in: :path, type: :string, required: true, description: "Path inside the EPUB, e.g. OEBPS/text/ch1.xhtml"]
    ],
    responses: [
      ok: {"Entry", "application/octet-stream", %OpenApiSpex.Schema{type: :string, format: :binary}},
      forbidden: {"Not a text book", "application/json", Schemas.Error},
      not_found: {"No such entry", "application/json", Schemas.Error}
    ]

  def entry(conn, %{"id" => id, "entry" => parts}) do
    name = Enum.join(parts, "/")

    with {:ok, file} <- epub_file(conn, id),
         {:ok, data} <- Epub.read(file.path, name) do
      conn
      |> put_resp_content_type(content_type(file.path, name), nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", @entry_csp)
      # Private: files are access-controlled. An entry of an unchanged file never changes.
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_resp(200, data)
    else
      error -> fail(conn, error)
    end
  end

  defp epub_file(conn, id) do
    book = Library.get_book!(conn.assigns.access, id) |> Stashix.Repo.preload(:files)

    cond do
      Library.text_book_file(book, :epub) -> {:ok, Library.text_book_file(book, :epub)}
      Enum.any?(book.files, &(&1.format == :epub)) -> {:error, :forbidden}
      true -> {:error, :not_found}
    end
  end

  # The package's media type when it lists the entry, else the extension's.
  defp content_type(path, name) do
    with {:ok, %{manifest: manifest}} <- Epub.package(path),
         %{media_type: type} when type != "" <- Enum.find_value(manifest, fn {_, i} -> i.href == name && i end) do
      type
    else
      _ -> MIME.from_path(name)
    end
  end

  defp fail(conn, {:error, :forbidden}), do: conn |> put_status(:forbidden) |> json(%{error: "not a text book"})
  defp fail(conn, _error), do: conn |> put_status(:not_found) |> json(%{error: "not found"})
end
