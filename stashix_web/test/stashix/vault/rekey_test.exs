# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault.RekeyTest do
  use Stashix.DataCase, async: true

  import Ecto.Query

  alias Cloak.Ciphers.AES.GCM
  alias Stashix.Metadata.SourceConfig
  alias Stashix.Vault.Rekey

  defp source(key, config) do
    %SourceConfig{} |> SourceConfig.changeset(%{source_key: key, config: config}) |> Repo.insert!()
  end

  defp raw_config(%{id: id}) do
    {:ok, id} = Ecto.UUID.dump(id)
    Repo.one!(from s in "metadata_sources", where: s.id == ^id, select: s.config)
  end

  defp set_raw_config(%{id: id}, ciphertext) do
    {:ok, id} = Ecto.UUID.dump(id)
    Repo.update_all(from(s in "metadata_sources", where: s.id == ^id), set: [config: ciphertext])
  end

  defp v1(plaintext, key) do
    {:ok, ciphertext} = GCM.encrypt(plaintext, tag: "AES.GCM.V1", key: key, iv_length: 12)
    ciphertext
  end

  defp tag(ciphertext), do: Cloak.Tags.Decoder.decode(ciphertext).tag

  defp vault_key do
    {_, opts} = Application.fetch_env!(:stashix, Stashix.Vault)[:ciphers][:default]
    opts[:key]
  end

  test "rewrites V1 values under the default cipher, keeping the plaintext" do
    legacy = source("legacy", %{})
    set_raw_config(legacy, v1(~s({"api_key":"secret"}), vault_key()))
    current = source("current", %{"api_key" => "other"})
    current_raw = raw_config(current)

    assert Rekey.run() == 1
    assert tag(raw_config(legacy)) == "AES.GCM.V2"
    assert Repo.get!(SourceConfig, legacy.id).config == %{"api_key" => "secret"}
    assert raw_config(current) == current_raw

    assert Rekey.run() == 0
  end

  @tag :capture_log
  test "leaves values it can't decrypt untouched" do
    lost = source("lost", %{})
    ciphertext = v1(~s({"api_key":"secret"}), :crypto.strong_rand_bytes(32))
    set_raw_config(lost, ciphertext)

    assert Rekey.run() == 0
    assert raw_config(lost) == ciphertext
  end
end
