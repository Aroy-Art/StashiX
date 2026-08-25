defmodule Stashix.Library.SeriesExternalId do
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

  schema "series_external_ids" do
    field :source, Ecto.Enum, values: @information_sources
    field :source_id, :string
    field :is_primary, :boolean, default: false

    belongs_to :series, Stashix.Library.Series

    timestamps()
  end

  def changeset(ext_id, attrs) do
    ext_id
    |> cast(attrs, [:source, :source_id, :is_primary, :series_id])
    |> validate_required([:source, :source_id, :series_id])
    |> unique_constraint([:series_id, :source])
  end
end
