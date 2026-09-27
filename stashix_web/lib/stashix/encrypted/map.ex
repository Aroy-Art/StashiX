defmodule Stashix.Encrypted.Map do
  @moduledoc false
  use Cloak.Ecto.Map, vault: Stashix.Vault
end
