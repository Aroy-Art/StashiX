# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.DownloadHelper do
  @moduledoc """
  Sends book files as downloads: one file as itself, several as a ZIP that is
  streamed while it is written (see `Stashix.Media.ZipStream`).
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2, send_download: 3]

  alias Stashix.Library.BookFile
  alias Stashix.Media.ZipStream

  @formats Map.new(Ecto.Enum.values(BookFile, :format), &{to_string(&1), &1})

  @doc """
  The formats asked for in a `formats` param ("cbz,pdf"), or nil (every
  format) when it is missing. Unknown names are ignored.
  """
  def requested_formats(%{"formats" => formats}) when is_binary(formats) do
    formats |> String.split(",", trim: true) |> Enum.flat_map(&List.wrap(@formats[String.trim(&1)]))
  end

  def requested_formats(_params), do: nil

  def filter_formats(files, nil), do: files
  def filter_formats(files, formats), do: Enum.filter(files, &(&1.format in formats))

  @doc """
  Sends `files`: a single file directly, more than one as `zip_name`.zip.
  Responds 404 when there is nothing to send.
  """
  def send_files(conn, [], _zip_name), do: not_found(conn)

  def send_files(conn, [file], _zip_name) do
    if File.regular?(file.path),
      do: send_download(conn, {:file, file.path}, filename: Path.basename(file.path)),
      else: not_found(conn)
  end

  def send_files(conn, files, zip_name) do
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
