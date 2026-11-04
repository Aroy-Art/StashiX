# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault.LegacyCipher do
  @moduledoc """
  Read-only AES-GCM cipher for values written under the `AES.GCM.V1` tag.

  V1 values were encrypted with either `STASHIX_ENCRYPTION_KEY` or, when that
  was unset, a key derived from `JWT_SECRET`. Both carry the same tag and Cloak
  picks a cipher by tag alone, so a plain retired cipher can only hold one of
  them. This one tries each key in `:keys` until one authenticates.

  Takes the same options as `Cloak.Ciphers.AES.GCM`, with `:keys` in place of
  `:key`.
  """
  @behaviour Cloak.Cipher

  alias Cloak.Ciphers.AES.GCM

  @impl Cloak.Cipher
  def encrypt(_plaintext, _opts), do: :error

  @impl Cloak.Cipher
  def decrypt(ciphertext, opts) do
    {keys, opts} = Keyword.pop!(opts, :keys)

    Enum.find_value(keys, :error, fn key ->
      case GCM.decrypt(ciphertext, Keyword.put(opts, :key, key)) do
        {:ok, plaintext} when is_binary(plaintext) -> {:ok, plaintext}
        _ -> nil
      end
    end)
  end

  @impl Cloak.Cipher
  def can_decrypt?(ciphertext, opts), do: GCM.can_decrypt?(ciphertext, opts)
end
