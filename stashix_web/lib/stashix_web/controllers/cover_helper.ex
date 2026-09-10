defmodule StashixWeb.CoverHelper do
  import Plug.Conn

  alias Stashix.Media.ImageResizer

  @valid_sizes ~w(sx s m l lg xl)

  def serve_cover(conn, path, size_str) when size_str in @valid_sizes do
    size = String.to_existing_atom(size_str)
    format = if webp_supported?(conn), do: :webp, else: :jpeg
    content_type = if format == :webp, do: "image/webp", else: "image/jpeg"

    case ImageResizer.resize(path, size, format) do
      {:ok, resized_path} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=86400")
        |> put_resp_header("vary", "Accept")
        |> send_file(200, resized_path)

      {:error, _} ->
        serve_cover(conn, path, nil)
    end
  end

  def serve_cover(conn, path, _size) do
    conn
    |> put_resp_content_type(MIME.from_path(path))
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_file(200, path)
  end

  defp webp_supported?(conn) do
    conn
    |> get_req_header("accept")
    |> Enum.any?(&String.contains?(&1, "image/webp"))
  end
end
