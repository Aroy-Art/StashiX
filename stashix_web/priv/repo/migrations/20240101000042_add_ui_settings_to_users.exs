# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddUiSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :ui_settings, :map, null: false, default: %{}
    end
  end
end
