defmodule Stashix.Repo.Migrations.CreateHealthCheckResults do
  use Ecto.Migration

  def change do
    create table(:health_check_results, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :library_id, references(:libraries, type: :binary_id, on_delete: :delete_all),
        null: false

      add :book_file_id, references(:book_files, type: :binary_id, on_delete: :delete_all)
      add :check_type, :string, null: false
      add :file_path, :string, null: false
      add :status, :string, null: false
      add :error_message, :text
      add :checked_at, :naive_datetime, null: false

      timestamps()
    end

    create index(:health_check_results, [:library_id, :check_type])
    create index(:health_check_results, [:book_file_id])
    create unique_index(:health_check_results, [:book_file_id, :check_type])
    create unique_index(:health_check_results, [:library_id, :file_path, :check_type])
  end
end
