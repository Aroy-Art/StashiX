defmodule Stashix.Library.SeriesAlternativeName do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "series_alternative_names" do
    field :name, :string
    field :lang, :string, default: "en"
    field :external_id, :string

    belongs_to :series, Stashix.Library.Series

    timestamps()
  end

  def changeset(alt_name, attrs) do
    alt_name
    |> cast(attrs, [:series_id, :name, :lang, :external_id])
    |> validate_required([:series_id, :name])
    |> unique_constraint([:series_id, :name])
  end
end
