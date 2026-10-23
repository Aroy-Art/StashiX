# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault do
  @moduledoc """
  Cloak vault for encrypting secrets at rest (metadata source credentials, cookies).

  The key comes from `STASHIX_ENCRYPTION_KEY` (base64, 32 bytes). When unset it is
  derived from `JWT_SECRET` so existing installs keep working; set an explicit key
  in production. See `config/runtime.exs`.
  """
  use Cloak.Vault, otp_app: :stashix
end
