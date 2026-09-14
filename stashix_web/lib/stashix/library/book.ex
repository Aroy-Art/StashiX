defmodule Stashix.Library.Book do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @age_ratings [:unknown, :everyone, :teen, :teen_plus, :mature, :adult, :explicit]

  schema "books" do
    field :title, :string
    field :issue_number, :decimal
    field :volume, :integer
    field :year, :integer
    field :page_count, :integer, default: 0
    field :language, :string, default: "en"
    field :summary, :string
    field :age_rating, Ecto.Enum, values: @age_ratings, default: :unknown
    field :adult, :boolean, default: false
    field :type, :string, default: "issue"
    field :deleted_at, :naive_datetime
    field :collection_title, :string
    field :alternative_number, :string
    field :isbn, :string
    field :upc, :string
    field :community_rating, :float
    field :source_format, :string, virtual: true

    belongs_to :library, Stashix.Library.Library
    belongs_to :series, Stashix.Library.Series
    belongs_to :imprint, Stashix.Library.Imprint
    many_to_many :publishers, Stashix.Library.Publisher, join_through: "book_publishers", on_replace: :delete
    has_one :cover, Stashix.Library.BookCover
    has_many :reading_progress, Stashix.Library.ReadingProgress
    has_many :files, Stashix.Library.BookFile

    timestamps()
  end

  def changeset(book, attrs) do
    book
    |> cast(attrs, [
      :title,
      :issue_number,
      :volume,
      :year,
      :page_count,
      :language,
      :summary,
      :age_rating,
      :adult,
      :type,
      :deleted_at,
      :collection_title,
      :alternative_number,
      :isbn,
      :upc,
      :community_rating,
      :library_id,
      :series_id,
      :imprint_id
    ])
    |> validate_required([:title, :library_id])
  end
end
