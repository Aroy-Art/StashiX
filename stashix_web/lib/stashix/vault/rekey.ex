# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Vault.Rekey do
  @moduledoc """
  Re-encrypts `AES.GCM.V1` values under the current default cipher.

  V1 values may be encrypted with a key derived from `JWT_SECRET`, so they stop
  decrypting once that secret is rotated. Rewriting them with
  `STASHIX_ENCRYPTION_KEY` removes that dependency. Runs once at startup; rows
  already on the default cipher are skipped, so later runs do nothing.

  Works on the raw column so the stored plaintext is copied byte for byte. Each
  update matches the old ciphertext, so a row changed in the meantime is left
  for the next run instead of being overwritten.
  """
  require Logger

  import Ecto.Query

  alias Stashix.Repo

  @legacy_tag "AES.GCM.V1"

  # {table, encrypted column}. Primary keys are binary UUIDs.
  @columns [{"metadata_sources", :config}]

  def child_spec(_arg) do
    %{id: __MODULE__, start: {Task, :start_link, [&run/0]}, restart: :temporary}
  end

  @doc "Re-encrypts every legacy value. Returns how many rows were rewritten."
  def run do
    count = Enum.sum(for {table, column} <- @columns, do: rekey(table, column))
    if count > 0, do: Logger.info("Re-encrypted #{count} stored secret(s) with STASHIX_ENCRYPTION_KEY")
    count
  end

  defp rekey(table, column) do
    from(r in table, where: not is_nil(field(r, ^column)), select: {r.id, field(r, ^column)})
    |> Repo.all()
    |> Enum.count(fn {id, ciphertext} -> legacy?(ciphertext) and rewrite(table, column, id, ciphertext) end)
  end

  defp legacy?(ciphertext) do
    match?(%{tag: @legacy_tag}, Cloak.Tags.Decoder.decode(ciphertext))
  end

  defp rewrite(table, column, id, ciphertext) do
    with {:ok, plaintext} <- Stashix.Vault.decrypt(ciphertext),
         {:ok, reencrypted} <- Stashix.Vault.encrypt(plaintext) do
      {updated, _} =
        from(r in table, where: r.id == ^id and field(r, ^column) == ^ciphertext)
        |> Repo.update_all(set: [{column, reencrypted}])

      updated == 1
    else
      _ ->
        Logger.warning(
          "Could not decrypt #{table}.#{column} for #{Ecto.UUID.cast!(id)}; " <>
            "it was encrypted with a key that is no longer configured"
        )

        false
    end
  end
end
