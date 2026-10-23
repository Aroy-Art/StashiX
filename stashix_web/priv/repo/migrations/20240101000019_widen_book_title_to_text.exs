# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.WidenBookTitleToText do
  use Ecto.Migration

  def change do
    alter table(:books) do
      modify :title, :text, null: false, from: {:string, null: false}
    end
  end
end
