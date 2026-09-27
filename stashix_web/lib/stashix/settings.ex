defmodule Stashix.Settings do
  @moduledoc """
  Global key/value application settings stored in `app_settings`.

  Each key holds a map. `get/2` merges the stored map over the defaults so new
  default keys appear without a migration.
  """
  alias Stashix.Repo
  alias Stashix.Settings.AppSetting

  @defaults %{
    "metadata" => %{
      "auto_match_threshold" => 0.9,
      "auto_match_margin" => 0.1,
      "overwrite_mode" => "replace",
      "write_to_files" => true,
      "write_comicinfo" => true
    }
  }

  def defaults(key), do: Map.get(@defaults, key, %{})

  def get(key) when is_binary(key) do
    stored =
      case Repo.get(AppSetting, key) do
        nil -> %{}
        %AppSetting{value: value} -> value
      end

    Map.merge(defaults(key), stored)
  end

  def put(key, value) when is_binary(key) and is_map(value) do
    %AppSetting{key: key}
    |> AppSetting.changeset(%{value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: NaiveDateTime.utc_now(:second)]],
      conflict_target: :key
    )
  end

  def metadata, do: get("metadata")
end
