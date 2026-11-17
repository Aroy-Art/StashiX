# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.AddCanDownloadToLibraryPermissions do
  use Ecto.Migration

  # Off for everyone until an admin turns it on per library.
  def change do
    alter table(:library_permissions) do
      add :can_download, :boolean, null: false, default: false
    end
  end
end
