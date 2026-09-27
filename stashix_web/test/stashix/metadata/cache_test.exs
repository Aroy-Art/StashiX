defmodule Stashix.Metadata.CacheTest do
  use Stashix.DataCase, async: false

  import Stashix.MetadataFixtures

  alias Stashix.Metadata.{Cache, HTTP, Sources}
  alias Stashix.Metadata.Sources.{ComicVine, Metron}

  setup do
    enable_metron!()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Req.Test.stub(HTTP, fn conn ->
      Agent.update(counter, &(&1 + 1))

      case conn.request_path do
        "/api/issue/111/" -> Req.Test.json(conn, metron_issue())
        "/api/issues/" -> Req.Test.json(conn, %{"status_code" => 1, "results" => []})
        "/api/search/" -> Req.Test.json(conn, %{"status_code" => 100, "error" => "Invalid API Key"})
      end
    end)

    %{calls: fn -> Agent.get(counter, & &1) end}
  end

  test "second identical request is served from the cache", %{calls: calls} do
    ctx = HTTP.context(Sources.get("metron"))
    assert {:ok, a} = Metron.fetch_issue("111", ctx)
    assert {:ok, ^a} = Metron.fetch_issue("111", HTTP.context(Sources.get("metron")))
    assert calls.() == 1
    assert Cache.count() == 1
  end

  test "refresh bypasses reads but still stores", %{calls: calls} do
    source = Sources.get("metron")
    {:ok, _} = Metron.fetch_issue("111", HTTP.context(source))
    {:ok, _} = Metron.fetch_issue("111", HTTP.context(source, refresh: true))
    assert calls.() == 2
    assert Cache.count() == 1
  end

  test "expired entries are ignored and pruned", %{calls: calls} do
    source = Sources.get("metron")
    {:ok, _} = Metron.fetch_issue("111", HTTP.context(source))
    Repo.update_all(Cache, set: [expires_at: ~N[2000-01-01 00:00:00]])

    {:ok, _} = Metron.fetch_issue("111", HTTP.context(source))
    assert calls.() == 2

    Repo.update_all(Cache, set: [expires_at: ~N[2000-01-01 00:00:00]])
    assert Cache.prune() == 1
  end

  test "secrets are excluded from key and stored url; error payloads are not cached", %{calls: calls} do
    %{config: row} = Sources.get("comic_vine")
    {:ok, _} = Sources.update(row, %{"config" => %{"api_key" => "SECRET1"}})
    ctx = HTTP.context(Sources.get("comic_vine"))

    {:ok, []} = ComicVine.search_issues(%{series_id: "5", number: "1"}, ctx)
    [entry] = Repo.all(Cache)
    refute entry.url =~ "SECRET1"

    # a different key hits the same cache entry
    %{config: row} = Sources.get("comic_vine")
    {:ok, _} = Sources.update(row, %{"config" => %{"api_key" => "SECRET2"}})
    {:ok, []} = ComicVine.search_issues(%{series_id: "5", number: "1"}, HTTP.context(Sources.get("comic_vine")))
    assert calls.() == 1

    assert {:error, :unauthorized} = ComicVine.search_series(%{name: "x"}, ctx)
    assert Cache.count() == 1
  end
end
