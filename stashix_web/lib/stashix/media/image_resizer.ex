defmodule Stashix.Media.ImageResizer do
  @quality 75
  @max_width 2000

  @sizes %{sx: 80, s: 150, m: 300, l: 450, lg: 600, xl: 900}

  def sizes, do: @sizes

  def size_width(size) when is_atom(size), do: Map.get(@sizes, size)

  # Resize to a predefined named size and cache the result to disk.
  def resize(source_path, size, format \\ :jpeg) when is_atom(size) do
    case Map.get(@sizes, size) do
      nil -> {:error, :invalid_size}
      width -> do_resize_cached(source_path, width, size, format)
    end
  end

  # Resize to an arbitrary pixel width without saving to disk. Returns binary.
  def resize_transient(source_path, width, format \\ :jpeg)
      when is_integer(width) and width > 0 do
    width = min(width, @max_width)
    vips_suffix = if format == :webp, do: ".webp[Q=#{@quality}]", else: ".jpg[Q=#{@quality}]"

    with {:ok, image} <- Image.thumbnail(source_path, "#{width}x9999"),
         {:ok, binary} <- Vix.Vips.Image.write_to_buffer(image, vips_suffix) do
      {:ok, binary}
    end
  end

  defp do_resize_cached(source_path, width, size, format) do
    cache_dir = resized_cache_dir()
    File.mkdir_p!(cache_dir)

    ext = if format == :webp, do: "webp", else: "jpg"
    cache_key = :crypto.hash(:md5, source_path) |> Base.encode16(case: :lower)
    cached_path = Path.join(cache_dir, "#{cache_key}-#{size}.#{ext}")

    if File.exists?(cached_path) do
      {:ok, cached_path}
    else
      with {:ok, image} <- Image.thumbnail(source_path, "#{width}x9999"),
           {:ok, _} <- Image.write(image, cached_path, quality: @quality) do
        {:ok, cached_path}
      end
    end
  end

  defp resized_cache_dir do
    Application.get_env(:stashix, :image_cache_dir, "/tmp/stashix/cache/images/resized")
  end
end
