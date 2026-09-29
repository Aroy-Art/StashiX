defmodule StashixWeb.MetadataImageController do
  @moduledoc "Serves metadata source images (e.g. Identify dialog covers) through `Stashix.Metadata.ImageProxy`."
  use StashixWeb, :controller

  alias Stashix.Metadata.ImageProxy

  def show(conn, %{"url" => url}) do
    case ImageProxy.fetch(url) do
      {:file, path, type} ->
        conn |> image_headers(type) |> send_file(200, path)

      {:binary, body, type} ->
        conn |> image_headers(type) |> send_resp(200, body)

      {:error, :forbidden} ->
        send_resp(conn, 403, "")

      {:error, :not_found} ->
        send_resp(conn, 404, "")

      {:error, _} ->
        send_resp(conn, 502, "")
    end
  end

  def show(conn, _params), do: send_resp(conn, 400, "")

  defp image_headers(conn, type) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("cache-control", "private, max-age=86400")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
  end
end
