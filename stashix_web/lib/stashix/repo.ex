# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Repo do
  use Ecto.Repo,
    otp_app: :stashix,
    adapter: Ecto.Adapters.Postgres
end
