defmodule Stashix.Media.Thumbnail do
  alias Stashix.Media.Extractor

  def generate(book_path, dest_path) do
    with {:ok, data} <- Extractor.get_page(book_path, 0),
         :ok <- File.write(dest_path, data) do
      {:ok, dest_path}
    end
  end
end
