defmodule Stashix.Repo.Migrations.AddUiSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :ui_settings, :map, null: false, default: %{}
    end
  end
end
