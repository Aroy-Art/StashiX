defmodule Stashix.Media.Thumbnail do
  alias Stashix.Media.Extractor

  def generate(book_path, dest_path) do
    case Extractor.get_page(book_path, 0) do
      {:ok, data} ->
        case File.write(dest_path, data) do
          :ok -> {:ok, dest_path}
          error -> error
        end

      error ->
        error
    end
  end
end
