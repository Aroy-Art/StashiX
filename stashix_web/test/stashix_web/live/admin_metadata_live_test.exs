defmodule StashixWeb.AdminMetadataLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Stashix.MetadataFixtures

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Metadata.Sources

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "admin@example.com", username: "admin", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)

    conn =
      conn
      |> Plug.Test.init_test_session(%{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    %{conn: conn}
  end

  test "sources auto-save, never echo secrets and can only be enabled after a passing test", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/metadata")
    assert html =~ "Metron"
    assert html =~ "Comic Vine"
    assert html =~ "Grand Comics Database"

    view
    |> form("#source-form-metron", %{
      "config" => %{"username" => "bob", "password" => "hunter2"},
      "rate_limit_per_minute" => "10"
    })
    |> render_change()

    %{config: row} = Sources.get("metron")
    assert row.config["password"] == "hunter2"
    assert row.rate_limit_per_minute == 10
    refute render(view) =~ "hunter2"
    assert render(view) =~ "Saved"

    # enabling is blocked until the connection test passes
    assert view |> element("button[phx-value-key=metron][phx-value-field=enabled][disabled]") |> has_element?()
    render_click(view, "toggle_source", %{"key" => "metron", "field" => "enabled"})
    refute Sources.get("metron").config.enabled

    Req.Test.stub(Stashix.Metadata.HTTP, fn conn -> Req.Test.json(conn, %{"count" => 1, "results" => []}) end)
    Req.Test.allow(Stashix.Metadata.HTTP, self(), view.pid)
    assert :ok = Stashix.Metadata.test_source("metron")
    send(view.pid, {:source_tested, "metron"})

    view |> element("button[phx-value-key=metron][phx-value-field=enabled]") |> render_click()
    assert Sources.get("metron").config.enabled
  end

  test "settings tab saves", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/admin/metadata/settings")

    view
    |> form("#metadata-settings-form", %{
      "settings" => %{
        "auto_match_threshold" => "80",
        "auto_match_margin" => "5",
        "overwrite_mode" => "fill",
        "write_to_files" => "false",
        "write_comicinfo" => "true",
        "cache_search_hours" => "6",
        "cache_detail_days" => "0"
      }
    })
    |> render_change()

    s = Stashix.Settings.metadata()
    assert s["auto_match_threshold"] == 0.8
    assert s["overwrite_mode"] == "fill"
    assert s["write_to_files"] == false
    assert s["cache_search_hours"] == 6
    assert s["cache_detail_days"] == 0
  end

  test "review tab opens identify dialog and applies a candidate", %{conn: conn} do
    tmp = Path.join(System.tmp_dir!(), "stashix_lv_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    Stashix.Settings.put("metadata", %{"write_to_files" => false})

    lib = library_fixture(tmp)
    series = series_fixture(lib)
    book = book_fixture(lib, series)
    enable_metron!()

    Req.Test.stub(Stashix.Metadata.HTTP, fn conn ->
      case conn.request_path do
        "/api/series/" ->
          Req.Test.json(
            conn,
            metron_series_list([metron_series_item(55, "Batman", 2016), metron_series_item(56, "Batman", 2016)])
          )

        "/api/issue/" ->
          sid = String.to_integer(conn.query_params["series_id"])
          Req.Test.json(conn, metron_series_list([metron_issue_item(100 + sid, sid, "Batman", "1", "2016-08-01")]))

        "/api/issue/" <> _ ->
          Req.Test.json(conn, metron_issue())
      end
    end)

    {:review, review} = Stashix.Metadata.identify_book(book)

    {:ok, _view, html} = live(conn, ~p"/admin/metadata/review")
    assert html =~ "Identify"

    {:ok, view, _} = live(conn, ~p"/admin/metadata/review?identify=#{review.id}")
    Req.Test.allow(Stashix.Metadata.HTTP, self(), view.pid)

    {:ok, book} = Library.update_book(book, %{summary: "Keep me", upc: "000"})

    view |> element("#identify-review button[phx-value-idx='0']") |> render_click()
    html = render_async(view)
    assert html =~ "I Am Gotham, Part One"

    # filled fields are not pre-selected; opt in to overwrite UPC only
    refute view |> element("#identify-review-row-summary input[checked]") |> has_element?()
    assert view |> element("#identify-review-row-title input[checked]") |> has_element?()
    view |> element("#identify-review-row-upc input") |> render_click()

    view |> element("#identify-review button[phx-click=apply]") |> render_click()
    render_async(view)

    book = Library.get_book!(book.id)
    assert book.title == "I Am Gotham, Part One"
    assert book.summary == "Keep me"
    assert book.upc == "76194134182900111"
    assert Stashix.Metadata.count_reviews() == 0
  end
end
