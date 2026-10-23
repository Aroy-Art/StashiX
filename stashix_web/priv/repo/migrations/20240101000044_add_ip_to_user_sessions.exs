# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddIpToUserSessions do
  use Ecto.Migration

  def change do
    alter table(:user_sessions) do
      add :ip_address, :string
    end
  end
end
