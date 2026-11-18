# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Thumbnail do
  alias Stashix.Media.{Extractor, Fb2, Formats, Mobi}

  # The first page, or for Kindle and FictionBook books (no pages) the
  # cover picture they carry.
  def generate(book_path, dest_path) do
    with {:ok, data} <- cover(book_path, Formats.format(book_path)),
         :ok <- File.write(dest_path, data) do
      {:ok, dest_path}
    end
  end

  defp cover(path, format) do
    cond do
      Formats.mobi?(format) -> Mobi.cover(path)
      Formats.fb2?(format) -> Fb2.cover(path)
      true -> Extractor.get_page(path, 0)
    end
  end
end
