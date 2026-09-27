defmodule Stashix.Settings.AppSetting do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}

  schema "app_settings" do
    field :value, :map, default: %{}

    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:value])
    |> validate_required([:value])
  end
end
