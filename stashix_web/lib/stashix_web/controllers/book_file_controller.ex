# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.BookFileController do
  @moduledoc """
  Serves a book file's raw bytes for the text reader, with HTTP `Range`
  support so PDF.js fetches only the parts it shows.

  Only files that open in the text reader (`Stashix.Library.reader_kind/2`)
  are served: those can't be read any other way. Comics and scanned PDFs go
  through the page endpoint, so `can_download` still guards their files.
  """
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias StashixWeb.Schemas

  @content_types %{pdf: "application/pdf", epub: "application/epub+zip"}

  operation :show,
    summary: "Stream a text book's file",
    description:
      "Raw bytes of a file that opens in the text reader; honours a single `Range` (206). Other books are forbidden.",
    tags: ["Books", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      format: [
        in: :query,
        type: :string,
        description: "Which of the book's files (e.g. pdf); the preferred one when omitted"
      ],
      Range: [in: :header, type: :string, description: "One byte range, e.g. bytes=0-65535"]
    ],
    responses: [
      ok: {"Whole file", "application/octet-stream", %OpenApiSpex.Schema{type: :string, format: :binary}},
      partial_content:
        {"Requested range", "application/octet-stream", %OpenApiSpex.Schema{type: :string, format: :binary}},
      forbidden: {"Not a text book", "application/json", Schemas.Error},
      not_found: {"No file", "application/json", Schemas.Error},
      requested_range_not_satisfiable: {"Range outside the file", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id} = params) do
    book = Library.get_book!(conn.assigns.access, id) |> Stashix.Repo.preload(:files)
    format = params["format"] && String.to_existing_atom(params["format"])
    book_file = Library.get_preferred_book_file(book, format)

    cond do
      book_file == nil ->
        not_found(conn)

      Library.reader_kind(book, book_file) != :text ->
        conn |> put_status(:forbidden) |> json(%{error: "not a text book"})

      true ->
        case File.stat(book_file.path, time: :posix) do
          {:ok, %File.Stat{type: :regular, size: size, mtime: mtime}} ->
            conn
            |> put_resp_content_type(Map.get(@content_types, book_file.format, "application/octet-stream"), nil)
            |> put_resp_header("accept-ranges", "bytes")
            |> put_resp_header("etag", ~s(W/"#{size}-#{mtime}"))
            |> put_resp_header("content-disposition", "inline")
            # Private: files are access-controlled. Ranges of an unchanged file never change.
            |> put_resp_header("cache-control", "private, max-age=86400")
            |> send_range(book_file.path, size, get_req_header(conn, "range"))

          _ ->
            not_found(conn)
        end
    end
  end

  defp send_range(conn, path, size, [header]) do
    case parse_range(header, size) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> put_resp_content_type("application/json")
        |> send_resp(416, Jason.encode!(%{error: "range not satisfiable"}))

      # Several ranges or a malformed header: the whole file is a valid answer.
      :ignore ->
        send_file(conn, 200, path)
    end
  end

  defp send_range(conn, path, _size, _none), do: send_file(conn, 200, path)

  @doc false
  # One `bytes=` range, clamped to the file: `{:ok, first, last}` (inclusive),
  # `:unsatisfiable`, or `:ignore` for anything we don't serve as a range.
  def parse_range("bytes=" <> spec, size) do
    case String.split(spec, "-", parts: 2) do
      [first, last] when first != "" and not is_nil(last) ->
        with {first, ""} <- Integer.parse(first),
             {:ok, last} <- parse_last(String.trim(last), size) do
          cond do
            first >= size -> :unsatisfiable
            first > last -> :ignore
            true -> {:ok, first, min(last, size - 1)}
          end
        else
          _ -> :ignore
        end

      ["", suffix] ->
        case Integer.parse(suffix) do
          {0, ""} -> :unsatisfiable
          {n, ""} when n > 0 and size > 0 -> {:ok, max(size - n, 0), size - 1}
          {_, ""} -> :unsatisfiable
          _ -> :ignore
        end

      _ ->
        :ignore
    end
  end

  def parse_range(_header, _size), do: :ignore

  defp parse_last("", size), do: {:ok, size - 1}

  defp parse_last(last, _size) do
    case Integer.parse(last) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "no file"})
end
