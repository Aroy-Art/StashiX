# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Accounts.AppPassword do
  @moduledoc """
  A password for one reading app or device: OPDS clients sign in with the
  user's name and this instead of the account password, so a lost device can
  be shut out alone and never held the real password.

  The password itself is shown once, when it is made; only its SHA-256 is
  stored. It is long and random, so a plain hash is enough and checking it
  is cheap on every request (clients sign every cover and page fetch).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @prefix "stx_"

  schema "app_passwords" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :koreader_key, :binary, redact: true
    field :last_used_at, :utc_datetime

    belongs_to :user, Stashix.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(app_password, attrs) do
    app_password
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 80)
  end

  @doc "A new random password, as shown to the user."
  def generate, do: @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  def hash(password), do: :crypto.hash(:sha256, password)

  @doc """
  What KOReader's sync plugin sends for a password (the MD5 of it, in hex),
  hashed for storage like the password itself.
  """
  def koreader_key(password), do: hash(Base.encode16(:crypto.hash(:md5, password), case: :lower))

  @doc "Whether a string looks like one of ours (so it isn't an account password)."
  def app_password?(password), do: is_binary(password) and String.starts_with?(password, @prefix)
end
