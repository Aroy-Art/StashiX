defmodule Stashix.Metadata.Sources do
  @moduledoc """
  Registry of metadata source plugins and their persisted settings.

  Plugins are the modules listed in `config :stashix, :metadata_sources`. A DB row
  in `metadata_sources` is created on demand (disabled) for every registered
  plugin; rows whose plugin was removed from the list are ignored.
  """
  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Metadata.SourceConfig

  @masked "••••••••"

  def masked_value, do: @masked

  @doc "All registered plugin modules."
  def modules, do: Application.get_env(:stashix, :metadata_sources, [])

  @doc "Plugin module for a source key, or nil."
  def module(key) when is_binary(key), do: Enum.find(modules(), &(&1.key() == key))

  @doc """
  Every registered source as `%{module: mod, config: %SourceConfig{}}`, ordered by
  priority. Creates missing DB rows.
  """
  def list do
    mods = modules()
    keys = Enum.map(mods, & &1.key())

    existing =
      from(s in SourceConfig, where: s.source_key in ^keys)
      |> Repo.all()
      |> Map.new(&{&1.source_key, &1})

    mods
    |> Enum.with_index()
    |> Enum.map(fn {mod, idx} ->
      config = Map.get(existing, mod.key()) || create_default!(mod, (idx + 1) * 10)
      %{module: mod, config: config}
    end)
    |> Enum.sort_by(& &1.config.priority)
  end

  @doc "Enabled sources ordered by priority."
  def enabled, do: Enum.filter(list(), & &1.config.enabled)

  def get(key) do
    case module(key) do
      nil -> nil
      mod -> Enum.find(list(), &(&1.module == mod))
    end
  end

  defp create_default!(mod, priority) do
    %SourceConfig{}
    |> SourceConfig.changeset(%{
      source_key: mod.key(),
      priority: priority,
      config: default_config(mod)
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :source_key)
    |> case do
      %SourceConfig{id: nil} -> Repo.get_by!(SourceConfig, source_key: mod.key())
      row -> row
    end
  end

  defp default_config(mod) do
    mod.config_schema()
    |> Enum.filter(&Map.has_key?(&1, :default))
    |> Map.new(&{&1.key, &1.default})
  end

  @doc """
  Updates a source's settings. `config` params are merged into the stored map;
  secret/cookie fields left blank (or still showing the mask) keep their value.

  Changing the config invalidates the last connection test and disables the
  source until it is tested again (see `set_enabled/2`).
  """
  def update(%SourceConfig{} = row, attrs) do
    mod = module(row.source_key)
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      case Map.fetch(attrs, "config") do
        {:ok, params} when is_map(params) ->
          current = row.config || %{}
          merged = merge_config(mod, current, params)

          if merged == current do
            Map.delete(attrs, "config")
          else
            Map.merge(attrs, %{
              "config" => merged,
              "enabled" => false,
              "last_test_status" => nil,
              "last_test_message" => nil,
              "last_tested_at" => nil
            })
          end

        _ ->
          attrs
      end

    row
    |> SourceConfig.changeset(attrs)
    |> Repo.update()
  end

  @doc "Enables/disables a source. Enabling requires a successful connection test."
  def set_enabled(%SourceConfig{} = row, true) do
    if row.last_test_status == "ok",
      do: row |> SourceConfig.changeset(%{enabled: true}) |> Repo.update(),
      else: {:error, :untested}
  end

  def set_enabled(%SourceConfig{} = row, false),
    do: row |> SourceConfig.changeset(%{enabled: false}) |> Repo.update()

  defp merge_config(mod, current, params) do
    Enum.reduce(mod.config_schema(), current, fn field, acc ->
      case Map.fetch(params, field.key) do
        :error ->
          acc

        {:ok, value} ->
          value = cast_field(field.type, value)

          cond do
            field.type in [:secret, :cookies] and value in ["", nil, @masked] -> acc
            true -> Map.put(acc, field.key, value)
          end
      end
    end)
  end

  defp cast_field(:boolean, v), do: v in [true, "true", "on", "1"]

  defp cast_field(:integer, v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp cast_field(_, v) when is_binary(v), do: String.trim(v)
  defp cast_field(_, v), do: v

  @doc "Config map with secret values replaced by a mask, for rendering in forms."
  def masked_config(mod, config) do
    Map.new(mod.config_schema(), fn field ->
      value = Map.get(config || %{}, field.key)

      shown =
        if field.type in [:secret, :cookies] and value not in [nil, ""],
          do: @masked,
          else: value

      {field.key, shown}
    end)
  end

  @doc "True when every required config field has a value."
  def configured?(mod, config) do
    mod.config_schema()
    |> Enum.filter(&Map.get(&1, :required, false))
    |> Enum.all?(&(Map.get(config || %{}, &1.key) not in [nil, ""]))
  end

  @doc """
  True when the source's default limit allows no bursts (`{1, ms}`): its speed
  is configured as a minimum interval between requests, not requests/minute.
  """
  def spaced?(mod), do: match?({1, _}, mod.default_rate_limit())

  @doc "True when the source has per-endpoint hourly quotas."
  def endpoint_limits?(mod), do: function_exported?(mod, :endpoint_scope, 1)

  @doc "Effective source-wide rate limit as `{requests, per_ms}`."
  def rate_limit(mod, %SourceConfig{} = row) do
    cond do
      spaced?(mod) and pos_int?(row.request_interval_ms) -> {1, row.request_interval_ms}
      not spaced?(mod) and pos_int?(row.rate_limit_per_minute) -> {row.rate_limit_per_minute, 60_000}
      true -> mod.default_rate_limit()
    end
  end

  def rate_limit(mod, _), do: mod.default_rate_limit()

  @doc "Effective per-endpoint limit as `{requests, per_ms}`, or `nil` when the source has none."
  def endpoint_rate_limit(mod, row) do
    cond do
      not endpoint_limits?(mod) ->
        nil

      match?(%SourceConfig{endpoint_limit_per_hour: n} when is_integer(n) and n > 0, row) ->
        {row.endpoint_limit_per_hour, 3_600_000}

      true ->
        {mod.default_endpoint_limit_per_hour(), 3_600_000}
    end
  end

  defp pos_int?(n), do: is_integer(n) and n > 0

  @doc "Swaps priority with the neighbouring source (`:up` / `:down`)."
  def move(key, direction) do
    sources = list()
    idx = Enum.find_index(sources, &(&1.config.source_key == key))
    other_idx = if direction == :up, do: idx - 1, else: idx + 1

    if idx && other_idx >= 0 && other_idx < length(sources) do
      reordered =
        sources
        |> List.replace_at(idx, Enum.at(sources, other_idx))
        |> List.replace_at(other_idx, Enum.at(sources, idx))

      Repo.transaction(fn ->
        reordered
        |> Enum.with_index(1)
        |> Enum.each(fn {%{config: c}, i} ->
          c |> SourceConfig.changeset(%{priority: i * 10}) |> Repo.update!()
        end)
      end)
    end

    :ok
  end
end
