defmodule Stashix.Metadata.ImageProxy do
  @moduledoc """
  Fetches cover images from metadata sources on behalf of the browser and keeps
  them in a disk cache, so viewers never contact the source directly.

  Only URLs on a registered source's `image_hosts/0` are fetched (no open
  proxy), redirects are followed only onto allowed hosts, and only raster image
  types are accepted: the response is served from Stashix's own origin, so an
  SVG or HTML body must never get through.

  Files live in `:metadata_image_dir`, named by the SHA-256 of the URL, and are
  kept for the "Cache issue/series details" setting (0 disables caching).
  API rate limits don't apply: images come from the sources' CDNs.
  """

  @types %{
    "image/jpeg" => "jpg",
    "image/png" => "png",
    "image/webp" => "webp",
    "image/gif" => "gif",
    "image/avif" => "avif"
  }
  @max_bytes 15_000_000
  @max_redirects 3

  @doc """
  Returns `{:file, path, content_type}` (cached on disk),
  `{:binary, body, content_type}` (caching disabled) or `{:error, reason}`.
  """
  def fetch(url) do
    with {:ok, uri} <- allowed_uri(url) do
      ttl = ttl_seconds()
      hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)

      case ttl > 0 && cached(hash, ttl) do
        {:ok, path} -> {:file, path, type_of(path)}
        _ -> download(uri, hash, ttl)
      end
    end
  end

  @doc "True when `url` points at an image host of a registered source."
  def allowed?(url), do: match?({:ok, _}, allowed_uri(url))

  @doc "Deletes cached images older than the cache TTL. Returns the count."
  def prune do
    ttl = ttl_seconds()
    cutoff = System.os_time(:second) - ttl

    files()
    |> Enum.filter(fn path -> ttl == 0 or mtime(path) < cutoff end)
    |> Enum.count(&(File.rm(&1) == :ok))
  end

  @doc "Deletes all cached images. Returns the count."
  def clear, do: Enum.count(files(), &(File.rm(&1) == :ok))

  defp allowed_uri(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host)

    if (uri.scheme in ["https", "http"] and host) && Enum.any?(image_hosts(), &host_match?(host, &1)),
      do: {:ok, uri},
      else: {:error, :forbidden}
  end

  defp allowed_uri(_), do: {:error, :forbidden}

  defp host_match?(host, allowed), do: host == allowed or String.ends_with?(host, "." <> allowed)

  defp image_hosts do
    :stashix
    |> Application.get_env(:metadata_sources, [])
    |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :image_hosts, 0)))
    |> Enum.flat_map(& &1.image_hosts())
  end

  defp cached(hash, ttl) do
    case Path.wildcard(Path.join(dir(), hash <> ".*")) do
      [path | _] -> if mtime(path) >= System.os_time(:second) - ttl, do: {:ok, path}, else: :stale
      [] -> :miss
    end
  end

  defp download(uri, hash, ttl, hops \\ 0) do
    req =
      Req.new(
        url: uri,
        redirect: false,
        decode_body: false,
        retry: :transient,
        max_retries: 1,
        receive_timeout: 15_000,
        user_agent: "Stashix (+https://git.aroy-art.com/Aroy/Stashix)"
      )
      |> Req.merge(Application.get_env(:stashix, :metadata_req_options, []))

    case Req.get(req) do
      {:ok, %{status: status} = resp} when status in [301, 302, 303, 307, 308] and hops < @max_redirects ->
        with [location | _] <- Req.Response.get_header(resp, "location"),
             {:ok, next} <- allowed_uri(URI.to_string(URI.merge(uri, location))) do
          download(next, hash, ttl, hops + 1)
        else
          _ -> {:error, :forbidden}
        end

      {:ok, %{status: 200, body: body} = resp} when is_binary(body) ->
        type = resp |> Req.Response.get_header("content-type") |> List.first("") |> media_type()

        cond do
          not Map.has_key?(@types, type) -> {:error, :unsupported_type}
          byte_size(body) > @max_bytes -> {:error, :too_large}
          ttl == 0 -> {:binary, body, type}
          true -> store(hash, type, body)
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  # Write to a temp file and rename so concurrent requests never see a partial image.
  # A stale copy with another extension is removed so `cached/2` finds only one.
  defp store(hash, type, body) do
    path = Path.join(dir(), "#{hash}.#{@types[type]}")
    tmp = Path.join(dir(), "tmp-#{System.unique_integer([:positive])}-#{hash}")

    with :ok <- File.mkdir_p(dir()),
         :ok <- File.write(tmp, body),
         :ok <- File.rename(tmp, path) do
      dir() |> Path.join(hash <> ".*") |> Path.wildcard() |> Enum.reject(&(&1 == path)) |> Enum.each(&File.rm/1)
      {:file, path, type}
    else
      _ ->
        File.rm(tmp)
        {:binary, body, type}
    end
  end

  defp type_of(path) do
    ext = path |> Path.extname() |> String.trim_leading(".")
    Enum.find_value(@types, "application/octet-stream", fn {type, e} -> if e == ext, do: type end)
  end

  defp media_type(content_type),
    do: content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()

  defp files do
    dir()
    |> Path.join("*")
    |> Path.wildcard()
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: t}} -> t
      _ -> 0
    end
  end

  defp ttl_seconds, do: round((Stashix.Settings.metadata()["cache_detail_days"] || 30) * 86_400)

  defp dir, do: Application.fetch_env!(:stashix, :metadata_image_dir)
end
