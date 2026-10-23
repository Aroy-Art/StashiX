# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

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
