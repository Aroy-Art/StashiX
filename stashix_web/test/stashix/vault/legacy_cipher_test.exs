# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault.LegacyCipherTest do
  use ExUnit.Case, async: true

  alias Cloak.Ciphers.AES.GCM
  alias Stashix.Vault.LegacyCipher

  @explicit :crypto.strong_rand_bytes(32)
  @derived :crypto.strong_rand_bytes(32)
  @opts [tag: "AES.GCM.V1", keys: [@explicit, @derived], iv_length: 12]

  defp v1(plaintext, key) do
    {:ok, ciphertext} = GCM.encrypt(plaintext, tag: "AES.GCM.V1", key: key, iv_length: 12)
    ciphertext
  end

  test "decrypts V1 values written with any of its keys" do
    assert LegacyCipher.decrypt(v1("a", @explicit), @opts) == {:ok, "a"}
    assert LegacyCipher.decrypt(v1("b", @derived), @opts) == {:ok, "b"}
  end

  test "fails on a key it doesn't hold" do
    ciphertext = v1("c", :crypto.strong_rand_bytes(32))
    assert LegacyCipher.can_decrypt?(ciphertext, @opts)
    assert LegacyCipher.decrypt(ciphertext, @opts) == :error
  end

  test "only claims V1 values and never encrypts" do
    {:ok, v2} = GCM.encrypt("d", tag: "AES.GCM.V2", key: @explicit, iv_length: 12)
    refute LegacyCipher.can_decrypt?(v2, @opts)
    assert LegacyCipher.encrypt("d", @opts) == :error
  end
end
