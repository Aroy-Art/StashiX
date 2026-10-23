# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddReaderSettingsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :reader_settings, :map, default: %{}
    end
  end
end
