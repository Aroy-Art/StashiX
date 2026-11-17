# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.DownloadController do
  @moduledoc """
  Sends book files as downloads: one file as itself, several as a ZIP that is
  streamed while it is written (see `Stashix.Media.ZipStream`).

  Needs `can_download` on the library (see `Stashix.Library.Access`).
  """
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias Stashix.Library.{Access, BookFile}
  alias Stashix.Media.ZipStream
  alias StashixWeb.Schemas

  @formats Map.new(Ecto.Enum.values(BookFile, :format), &{to_string(&1), &1})

  operation :book,
    summary: "Download book files",
    description: "One file is sent as itself; several are sent as a ZIP. Needs download permission on the library.",
    tags: ["Books", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      formats: [in: :query, type: :string, description: "Comma-separated formats (e.g. cbz,pdf); all when omitted"]
    ],
    responses: [
      ok: {"File or ZIP", "application/octet-stream", %OpenApiSpex.Schema{type: :string, format: :binary}},
      forbidden: {"Downloads not allowed", "application/json", Schemas.Error},
      not_found: {"No matching file", "application/json", Schemas.Error}
    ]

  def book(conn, %{"id" => id} = params) do
    book = Library.get_book_with_series(conn.assigns.access, id)

    with :ok <- allowed(conn, book.library_id) do
      send_files(conn, filter_formats(book.files, requested_formats(params)), book.title)
    end
  end

  operation :series,
    summary: "Download a series as a ZIP",
    description:
      "Every visible issue's files in the chosen formats. A single file is sent as itself. Needs download permission on the library.",
    tags: ["Series", "Media"],
    parameters: [
      id: [in: :path, type: :integer, required: true],
      formats: [in: :query, type: :string, description: "Comma-separated formats (e.g. cbz,pdf); all when omitted"]
    ],
    responses: [
      ok: {"ZIP archive", "application/zip", %OpenApiSpex.Schema{type: :string, format: :binary}},
      forbidden: {"Downloads not allowed", "application/json", Schemas.Error},
      not_found: {"No matching file", "application/json", Schemas.Error}
    ]

  def series(conn, %{"id" => id} = params) do
    series = Library.get_series!(conn.assigns.access, id)

    with :ok <- allowed(conn, series.library_id) do
      files = conn.assigns.access |> Library.series_files(series.id) |> filter_formats(requested_formats(params))
      send_files(conn, files, series.name)
    end
  end

  defp allowed(conn, library_id) do
    if Access.can_download?(conn.assigns.access, library_id),
      do: :ok,
      else: conn |> put_status(:forbidden) |> json(%{error: "downloads not allowed"})
  end

  # The formats asked for in a `formats` param ("cbz,pdf"), or nil (every
  # format) when it is missing. Unknown names are ignored.
  defp requested_formats(%{"formats" => formats}) when is_binary(formats) do
    formats |> String.split(",", trim: true) |> Enum.flat_map(&List.wrap(@formats[String.trim(&1)]))
  end

  defp requested_formats(_params), do: nil

  defp filter_formats(files, nil), do: files
  defp filter_formats(files, formats), do: Enum.filter(files, &(&1.format in formats))

  # A single file is sent as itself, more than one as `zip_name`.zip.
  defp send_files(conn, [], _zip_name), do: not_found(conn)

  defp send_files(conn, [file], _zip_name) do
    if File.regular?(file.path),
      do: send_download(conn, {:file, file.path}, filename: Path.basename(file.path)),
      else: not_found(conn)
  end

  defp send_files(conn, files, zip_name) do
    case files |> entry_names() |> ZipStream.plan() do
      [] -> not_found(conn)
      entries -> send_zip(conn, entries, safe_name(zip_name) <> ".zip")
    end
  end

  defp send_zip(conn, entries, filename) do
    conn =
      conn
      |> put_resp_content_type("application/zip", nil)
      |> put_resp_header("content-disposition", disposition(filename))
      |> put_resp_header("content-length", to_string(ZipStream.size(entries)))
      |> send_chunked(200)

    # A client that goes away mid-download ends the write; the response is
    # already under way, so there is nothing left to tell it.
    case ZipStream.write(entries, conn, &chunk(&2, &1)) do
      {:ok, conn} -> conn
      {:error, _reason} -> halt(conn)
    end
  end

  # Each file under its own name, numbered when two share one (the same
  # filename in different folders).
  defp entry_names(files) do
    {named, _seen} =
      Enum.map_reduce(files, %{}, fn file, seen ->
        name = Path.basename(file.path)

        case Map.get(seen, name, 0) do
          0 -> {{name, file.path}, Map.put(seen, name, 1)}
          n -> {{numbered(name, n + 1), file.path}, Map.put(seen, name, n + 1)}
        end
      end)

    named
  end

  defp numbered(name, n) do
    ext = Path.extname(name)
    "#{Path.rootname(name)} (#{n})#{ext}"
  end

  # Titles can hold characters that are not allowed in filenames.
  defp safe_name(name) do
    case name |> String.replace(~r{[/\\:*?"<>|\x00-\x1f]}, "_") |> String.trim() do
      "" -> "download"
      safe -> safe
    end
  end

  # Same shape as `Phoenix.Controller.send_download/3`.
  defp disposition(filename) do
    encoded = URI.encode(filename, &URI.char_unreserved?/1)

    if encoded == filename,
      do: ~s[attachment; filename="#{filename}"],
      else: ~s[attachment; filename="#{encoded}"; filename*=utf-8''#{encoded}]
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "no file"})
end
