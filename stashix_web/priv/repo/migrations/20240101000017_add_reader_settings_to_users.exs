defmodule Stashix.Repo.Migrations.AddReaderSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :reader_settings, :map, default: %{}
    end
  end
end
