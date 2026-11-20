# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCreatorBioAndLinks do
  use Ecto.Migration

  # Author notes and links (from Calibre's notes and link fields).
  def change do
    alter table(:creators) do
      add :bio, :text
      add :url, :string
    end

    alter table(:series) do
      add :url, :string
    end
  end
end
