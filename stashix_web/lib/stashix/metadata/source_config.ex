defmodule Stashix.Metadata.SourceConfig do
  @moduledoc """
  Persisted per-source settings: enabled flag, priority, rate limit and the
  (encrypted) plugin config map described by the source's `config_schema/0`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "metadata_sources" do
    field :source_key, :string
    field :enabled, :boolean, default: false
    field :priority, :integer, default: 100
    field :auto_apply, :boolean, default: true
    field :config, Stashix.Encrypted.Map
    field :rate_limit_per_minute, :integer
    field :request_interval_ms, :integer
    field :endpoint_limit_per_hour, :integer
    field :last_tested_at, :naive_datetime
    field :last_test_status, :string
    field :last_test_message, :string

    timestamps()
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :source_key,
      :enabled,
      :priority,
      :auto_apply,
      :config,
      :rate_limit_per_minute,
      :request_interval_ms,
      :endpoint_limit_per_hour,
      :last_tested_at,
      :last_test_status,
      :last_test_message
    ])
    |> validate_required([:source_key])
    |> validate_number(:rate_limit_per_minute, greater_than: 0)
    |> validate_number(:request_interval_ms, greater_than: 0)
    |> validate_number(:endpoint_limit_per_hour, greater_than: 0)
    |> unique_constraint(:source_key)
  end
end
