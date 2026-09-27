defmodule Stashix.Metadata.SourcesTest do
  use Stashix.DataCase, async: false

  alias Stashix.Metadata.{Sources, SourceConfig}

  test "list/0 creates a disabled row for every registered plugin" do
    keys = Sources.list() |> Enum.map(& &1.config.source_key)
    assert Enum.sort(keys) == ["comic_vine", "gcd", "metron"]
    assert Enum.all?(Sources.list(), &(&1.config.enabled == false))
    assert Repo.aggregate(SourceConfig, :count) == 3
  end

  test "config is encrypted at rest and secrets are masked" do
    %{module: mod, config: row} = Sources.get("metron")
    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "bob", "password" => "hunter2"}})

    assert row.config["password"] == "hunter2"

    [raw] = Repo.query!("SELECT config FROM metadata_sources WHERE source_key = 'metron'").rows |> hd()
    refute raw =~ "hunter2"

    masked = Sources.masked_config(mod, row.config)
    assert masked["username"] == "bob"
    assert masked["password"] == Sources.masked_value()
  end

  test "blank or masked secret keeps the stored value" do
    %{config: row} = Sources.get("metron")
    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "bob", "password" => "hunter2"}})
    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "alice", "password" => ""}})
    {:ok, row} = Sources.update(row, %{"config" => %{"password" => Sources.masked_value()}})

    assert row.config == Map.merge(row.config, %{"username" => "alice", "password" => "hunter2"})
  end

  test "move/2 swaps priority" do
    [first, second | _] = Sources.list()
    Sources.move(second.config.source_key, :up)
    [new_first | _] = Sources.list()
    assert new_first.config.source_key == second.config.source_key
    refute new_first.config.source_key == first.config.source_key
  end

  test "rate_limit/2 prefers the configured per-minute value" do
    %{module: mod, config: row} = Sources.get("comic_vine")
    assert Sources.rate_limit(mod, row) == mod.default_rate_limit()
    {:ok, row} = Sources.update(row, %{"rate_limit_per_minute" => 12})
    assert Sources.rate_limit(mod, row) == {12, 60_000}
  end

  test "changing the config invalidates the connection test and disables the source" do
    %{config: row} = Sources.get("metron")
    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "bob", "password" => "x"}})
    {:ok, row} = Sources.update(row, %{"last_test_status" => "ok"})
    {:ok, row} = Sources.set_enabled(row, true)
    assert row.enabled

    # unchanged values (blank secret) keep the test result
    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "bob", "password" => ""}})
    assert row.enabled and row.last_test_status == "ok"

    {:ok, row} = Sources.update(row, %{"config" => %{"username" => "alice"}})
    refute row.enabled
    assert row.last_test_status == nil
  end

  test "set_enabled/2 refuses untested sources" do
    %{config: row} = Sources.get("gcd")
    assert Sources.set_enabled(row, true) == {:error, :untested}
    {:ok, row} = Sources.update(row, %{"last_test_status" => "error"})
    assert Sources.set_enabled(row, true) == {:error, :untested}
  end
end
