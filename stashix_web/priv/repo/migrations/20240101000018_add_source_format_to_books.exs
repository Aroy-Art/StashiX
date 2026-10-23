# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddSourceFormatToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :source_format, :string
    end
  end
end
