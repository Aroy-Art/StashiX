# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Encrypted.Map do
  @moduledoc false
  use Cloak.Ecto.Map, vault: Stashix.Vault
end
