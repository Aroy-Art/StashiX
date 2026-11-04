# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault do
  @moduledoc """
  Cloak vault for encrypting secrets at rest (metadata source credentials, cookies).

  The key comes from `STASHIX_ENCRYPTION_KEY` (base64, 32 bytes), required in
  production. Outside production it falls back to a key derived from `JWT_SECRET`.
  Values written before it was required stay readable through
  `Stashix.Vault.LegacyCipher` and are rewritten at startup by
  `Stashix.Vault.Rekey`. See `config/runtime.exs`.
  """
  use Cloak.Vault, otp_app: :stashix
end
