defmodule Stashix.Library.BookUrl do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "book_urls" do
    field :url, :string
    field :is_primary, :boolean, default: false

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(book_url, attrs) do
    book_url
    |> cast(attrs, [:book_id, :url, :is_primary])
    |> validate_required([:book_id, :url])
  end
end
