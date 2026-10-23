# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo.Migrations.DisableJit do
  use Ecto.Migration

  # JIT compilation costs far more than it saves on our small, index-friendly
  # queries: library search took ~56 ms with JIT and ~5.5 ms without.
  # Applies to new connections only, so the app must restart to pick it up.

  def up do
    execute """
    DO $$
    BEGIN
      EXECUTE format('ALTER DATABASE %I SET jit = off', current_database());
    END
    $$
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      EXECUTE format('ALTER DATABASE %I RESET jit', current_database());
    END
    $$
    """
  end
end
