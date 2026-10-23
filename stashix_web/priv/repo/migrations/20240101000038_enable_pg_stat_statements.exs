# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.EnablePgStatStatements do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS pg_stat_statements"
  end
end
