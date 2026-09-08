defmodule Stashix.Media.ImageResizer do
  @max_width 2000
  @quality 75

  def resize(source_path, width, format \\ :jpeg) when is_integer(width) and width > 0 do
    width = min(width, @max_width)
    cache_dir = resized_cache_dir()
    File.mkdir_p!(cache_dir)

    ext = if format == :webp, do: "webp", else: "jpg"
    cache_key = :crypto.hash(:md5, source_path) |> Base.encode16(case: :lower)
    cached_path = Path.join(cache_dir, "#{cache_key}-#{width}.#{ext}")

    if File.exists?(cached_path) do
      {:ok, cached_path}
    else
      do_resize(source_path, width, cached_path)
    end
  end

  defp do_resize(source_path, width, dest_path) do
    with {:ok, resized} <- Image.thumbnail(source_path, "#{width}x9999"),
         {:ok, _} <- Image.write(resized, dest_path, quality: @quality) do
      {:ok, dest_path}
    end
  end

  defp resized_cache_dir do
    Application.get_env(:stashix, :image_cache_dir, "/tmp/stashix/cache/images/resized")
  end
end
