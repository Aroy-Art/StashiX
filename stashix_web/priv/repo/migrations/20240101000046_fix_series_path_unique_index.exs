defmodule Stashix.Repo.Migrations.FixSeriesPathUniqueIndex do
  use Ecto.Migration

  def up do
    drop_if_exists index(:series, [:library_id, :path],
                     name: :series_library_id_path_unique_index
                   )

    create unique_index(:series, [:library_id, :path], name: :series_library_id_path_unique_index)
  end

  def down do
    drop_if_exists index(:series, [:library_id, :path],
                     name: :series_library_id_path_unique_index
                   )

    create unique_index(:series, [:library_id, :path],
             where: "path IS NOT NULL",
             name: :series_library_id_path_unique_index
           )
  end
end
