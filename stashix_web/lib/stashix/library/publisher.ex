defmodule Stashix.Library.Publisher do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @information_sources [
    :Metron,
    :"Comic Vine",
    :MangaUpdates,
    :AniList,
    :"League of Comic Geeks",
    :"Grand Comics Database",
    :Unknown
  ]

  schema "publishers" do
    field :name, :string
    field :source, Ecto.Enum, values: @information_sources
    field :source_id, :string
    field :hidden, :boolean, default: false

    has_many :imprints, Stashix.Library.Imprint
    many_to_many :series, Stashix.Library.Series, join_through: "series_publishers"
    many_to_many :books, Stashix.Library.Book, join_through: "book_publishers"

    belongs_to :canonical, __MODULE__, foreign_key: :canonical_publisher_id
    has_many :aliases, __MODULE__, foreign_key: :canonical_publisher_id

    timestamps()
  end

  def changeset(publisher, attrs) do
    publisher
    |> cast(attrs, [:name, :source, :source_id, :canonical_publisher_id, :hidden])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
