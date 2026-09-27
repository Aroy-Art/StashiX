defmodule Stashix.Metadata.MetronTest do
  use Stashix.DataCase, async: false

  import Stashix.MetadataFixtures

  alias Stashix.Metadata.{HTTP, Sources}
  alias Stashix.Metadata.Sources.Metron

  setup do
    enable_metron!()
    %{ctx: HTTP.context(Sources.get("metron"))}
  end

  test "sends basic auth and maps issue detail to MetronInfo-shaped metadata", %{ctx: ctx} do
    Req.Test.stub(HTTP, fn conn ->
      assert conn.request_path == "/api/issue/111/"
      assert ["Basic " <> encoded] = Plug.Conn.get_req_header(conn, "authorization")
      assert Base.decode64!(encoded) == "u:p"
      Req.Test.json(conn, metron_issue())
    end)

    assert {:ok, m} = Metron.fetch_issue("111", ctx)
    assert m.series == "Batman"
    assert m.issue_number == Decimal.new(1)
    assert m.title == "I Am Gotham, Part One"
    assert m.cover_date == ~D[2016-08-01]
    assert m.year == 2016
    assert m.publisher == "DC Comics"
    assert m.age_rating == :teen
    assert m.series_format == "Single Issue"
    assert m.genres == ["Super-Hero"]

    assert %{creator: "David Finch", roles: ["Penciller", "Cover"]} =
             Enum.find(m.credits, &(&1.creator == "David Finch"))

    assert [%{amount: amount, country: "US"}] = m.prices
    assert Decimal.equal?(amount, Decimal.new("2.99"))

    assert %{source: "Metron", source_id: "111", is_primary: true} in m.external_ids
    assert %{source: "Comic Vine", source_id: "540000", is_primary: false} in m.external_ids
    assert [%{source: "Metron", source_id: "55"}] = m.series_external_ids
  end

  test "search_series strips the year from display names", %{ctx: ctx} do
    Req.Test.stub(HTTP, fn conn ->
      assert conn.request_path == "/api/series/"
      assert conn.query_params["name"] == "Batman"
      Req.Test.json(conn, metron_series_list([metron_series_item(55, "Batman", 2016)]))
    end)

    assert {:ok, [c]} = Metron.search_series(%{name: "Batman"}, ctx)
    assert c.series_name == "Batman"
    assert c.id == "55"
    assert c.year == 2016
  end

  test "normalises auth errors", %{ctx: ctx} do
    Req.Test.stub(HTTP, fn conn -> Plug.Conn.send_resp(conn, 401, "nope") end)
    assert Metron.test_connection(ctx) == {:error, "Authentication failed (check credentials/cookies)"}
  end
end
