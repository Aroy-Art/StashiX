defmodule Stashix.Repo.Migrations.AddSourceFormatToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :source_format, :string
    end
  end
end
