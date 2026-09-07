defmodule Stashix.Library.Series do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @comic_formats [
    :"Single Issue",
    :"Trade Paperback",
    :Hardcover,
    :"Graphic Novel",
    :Annual,
    :"Digital Chapter",
    :Omnibus,
    :Compendium,
    :Treasury,
    :"Facsimile Edition",
    :Preview
  ]

  schema "series" do
    field :name, :string
    field :sort_name, :string
    field :volume, :integer
    field :language, :string, default: "en"
    field :format, Ecto.Enum, values: @comic_formats
    field :issue_count, :integer, default: 0
    field :volume_count, :integer, default: 0
    field :start_year, :integer
    field :end_year, :integer
    field :ongoing, :boolean, default: false
    field :adult, :boolean, default: false
    field :path, :string
    field :deleted_at, :naive_datetime
    field :cover_blurhash, :string, virtual: true

    belongs_to :library, Stashix.Library.Library
    has_many :books, Stashix.Library.Book
    many_to_many :publishers, Stashix.Library.Publisher, join_through: "series_publishers"
    has_many :external_ids, Stashix.Library.SeriesExternalId

    timestamps()
  end

  def changeset(series, attrs) do
    series
    |> cast(attrs, [
      :name,
      :sort_name,
      :volume,
      :language,
      :format,
      :issue_count,
      :volume_count,
      :start_year,
      :end_year,
      :ongoing,
      :adult,
      :path,
      :deleted_at,
      :library_id
    ])
    |> validate_required([:name, :library_id])
  end
end
