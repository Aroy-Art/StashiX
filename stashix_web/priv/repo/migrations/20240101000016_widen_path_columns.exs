defmodule Stashix.Repo.Migrations.WidenPathColumns do
  use Ecto.Migration

  def change do
    alter table(:books) do
      modify :path, :text, null: false
    end

    alter table(:series) do
      modify :path, :text
    end
  end
end
