defmodule Stashix.Library.BookFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @book_formats [:cbz, :cbr, :cb7, :epub, :pdf]

  schema "book_files" do
    field :path, :string
    field :format, Ecto.Enum, values: @book_formats
    field :file_size, :integer, default: 0
    field :file_hash, :string
    field :last_modified, :naive_datetime
    field :page_count, :integer, default: 0
    field :source_format, :string
    field :deleted_at, :naive_datetime

    belongs_to :book, Stashix.Library.Book
    timestamps()
  end

  def changeset(book_file, attrs) do
    book_file
    |> cast(attrs, [
      :path,
      :format,
      :file_size,
      :file_hash,
      :last_modified,
      :page_count,
      :source_format,
      :deleted_at,
      :book_id
    ])
    |> validate_required([:path, :format, :book_id])
    |> unique_constraint(:path)
  end
end
