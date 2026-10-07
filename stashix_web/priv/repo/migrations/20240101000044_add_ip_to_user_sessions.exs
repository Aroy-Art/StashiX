defmodule Stashix.Repo.Migrations.AddIpToUserSessions do
  use Ecto.Migration

  def change do
    alter table(:user_sessions) do
      add :ip_address, :string
    end
  end
end
