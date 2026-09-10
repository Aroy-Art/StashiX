defmodule StashixWeb.CoverHelper do
  import Plug.Conn

  alias Stashix.Media.ImageResizer

  @valid_sizes ~w(sx s m l lg xl)

  # s= predefined size → resize and cache to disk
  def serve_cover(conn, path, %{"s" => s} = _params) when s in @valid_sizes do
    size = String.to_existing_atom(s)
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
        serve_cover(conn, path, %{})
    end
  end

  # w= arbitrary width → resize on the fly, no disk write
  def serve_cover(conn, path, %{"w" => w} = _params) do
    case Integer.parse(w) do
      {width, _} when width > 0 ->
        format = if webp_supported?(conn), do: :webp, else: :jpeg
        content_type = if format == :webp, do: "image/webp", else: "image/jpeg"

        case ImageResizer.resize_transient(path, width, format) do
          {:ok, binary} ->
            conn
            |> put_resp_content_type(content_type)
            |> put_resp_header("vary", "Accept")
            |> send_resp(200, binary)

          {:error, _} ->
            serve_cover(conn, path, %{})
        end

      _ ->
        serve_cover(conn, path, %{})
    end
  end

  # No resize param → serve original file
  def serve_cover(conn, path, _params) do
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
