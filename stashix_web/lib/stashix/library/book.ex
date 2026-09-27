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
    field :cover_date, :date
    field :store_date, :date
    field :notes, :string
    field :community_rating, :float
    field :community_rating_count, :integer
    field :source_format, :string, virtual: true

    belongs_to :library, Stashix.Library.Library
    belongs_to :series, Stashix.Library.Series
    belongs_to :imprint, Stashix.Library.Imprint
    many_to_many :publishers, Stashix.Library.Publisher, join_through: "book_publishers", on_replace: :delete
    has_one :cover, Stashix.Library.BookCover
    has_many :reading_progress, Stashix.Library.ReadingProgress
    has_many :files, Stashix.Library.BookFile
    has_many :external_ids, Stashix.Library.BookExternalId
    has_many :credits, Stashix.Library.BookCredit
    has_many :genres, Stashix.Library.BookGenre
    has_many :tags, Stashix.Library.BookTag
    has_many :story_arcs, Stashix.Library.BookStoryArc
    has_many :stories, Stashix.Library.BookStory
    has_many :characters, Stashix.Library.BookCharacter
    has_many :teams, Stashix.Library.BookTeam
    has_many :universes, Stashix.Library.BookUniverse
    has_many :locations, Stashix.Library.BookLocation
    has_many :reprints, Stashix.Library.BookReprint
    has_many :urls, Stashix.Library.BookUrl
    has_many :prices, Stashix.Library.BookPrice

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
      :cover_date,
      :store_date,
      :notes,
      :community_rating,
      :community_rating_count,
      :library_id,
      :series_id,
      :imprint_id
    ])
    |> validate_required([:title, :library_id])
  end
end
