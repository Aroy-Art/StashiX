# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.RenderCache do
  @moduledoc """
  On-disk cache for pages rendered from a book file (PDF pages at a given
  width), so reopening a book or a second device doesn't render them again.

  The key includes the source file's mtime and size, so a changed file just
  misses; its old renders age out. A hit touches the file, and `prune/0`
  (daily, `Stashix.Media.Workers.PruneRenderCacheWorker`) deletes renders not
  used for `@max_age_days`.
  """

  @max_age_days 14

  @doc """
  The cached render of `variant` (e.g. `"p3-w1200"`) for `source`, or the
  result of `fun`, which is written to the cache when it succeeds.
  """
  @spec fetch(Path.t(), String.t(), (-> {:ok, binary()} | {:error, term()})) :: {:ok, binary()} | {:error, term()}
  def fetch(source, variant, fun) do
    case key(source) do
      {:ok, key} ->
        path = Path.join(dir(), "#{key}-#{variant}.jpg")

        case File.read(path) do
          {:ok, data} ->
            File.touch(path)
            {:ok, data}

          {:error, _} ->
            with {:ok, data} <- fun.() do
              write(path, data)
              {:ok, data}
            end
        end

      {:error, _} ->
        fun.()
    end
  end

  @doc "Deletes renders unused for #{@max_age_days} days. Returns the count."
  def prune do
    cutoff = System.os_time(:second) - @max_age_days * 86_400

    dir()
    |> Path.join("*.jpg")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %{mtime: mtime}} -> mtime < cutoff
        _ -> false
      end
    end)
    |> Enum.count(&(File.rm(&1) == :ok))
  end

  # Write to a temp name and rename, so a concurrent reader never sees half a file.
  defp write(path, data) do
    File.mkdir_p!(Path.dirname(path))
    tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"

    with :ok <- File.write(tmp, data), :ok <- File.rename(tmp, path) do
      :ok
    else
      _ -> File.rm(tmp)
    end
  end

  defp key(source) do
    with {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(source, time: :posix) do
      {:ok, :crypto.hash(:sha256, :erlang.term_to_binary({source, mtime, size})) |> Base.url_encode64(padding: false)}
    end
  end

  defp dir, do: Application.get_env(:stashix, :page_cache_dir, "/tmp/stashix/cache/pages")
end
