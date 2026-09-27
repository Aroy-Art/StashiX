defmodule Stashix.Library.BookExternalId do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources [
    :Metron,
    :"Comic Vine",
    :MangaUpdates,
    :AniList,
    :"League of Comic Geeks",
    :"Grand Comics Database",
    :Kitsu,
    :MangaDex,
    :Marvel,
    :MyAnimeList,
    :Unknown
  ]

  schema "book_external_ids" do
    field :source, Ecto.Enum, values: @sources
    field :source_id, :string
    field :is_primary, :boolean, default: false

    belongs_to :book, Stashix.Library.Book

    timestamps()
  end

  def changeset(eid, attrs) do
    eid
    |> cast(attrs, [:book_id, :source, :source_id, :is_primary])
    |> validate_required([:book_id, :source, :source_id])
    |> unique_constraint([:book_id, :source])
  end
end
