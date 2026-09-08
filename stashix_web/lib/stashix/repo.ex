defmodule Stashix.Repo do
  use Ecto.Repo,
    otp_app: :stashix,
    adapter: Ecto.Adapters.Postgres
end
