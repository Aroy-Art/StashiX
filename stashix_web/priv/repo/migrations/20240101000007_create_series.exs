defmodule Stashix.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    create table(:series, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :library_id, references(:libraries, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :sort_name, :string
      add :volume, :integer
      add :language, :string, default: "en"
      add :format, :comic_format
      add :issue_count, :integer, default: 0
      add :volume_count, :integer, default: 0
      add :publisher_id, references(:publishers, type: :uuid, on_delete: :nilify_all)
      add :ongoing, :boolean, default: false
      add :adult, :boolean, default: false
      add :path, :string

      timestamps()
    end

    create index(:series, [:library_id])
  end
end
