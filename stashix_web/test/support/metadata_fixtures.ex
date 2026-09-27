defmodule Stashix.MetadataFixtures do
  @moduledoc "Canned source API payloads and DB helpers for metadata tests."

  alias Stashix.Library
  alias Stashix.Metadata.Sources

  def metron_issue(overrides \\ %{}) do
    Map.merge(
      %{
        "id" => 111,
        "publisher" => %{"id" => 2, "name" => "DC Comics"},
        "imprint" => nil,
        "series" => %{
          "id" => 55,
          "name" => "Batman",
          "sort_name" => "Batman",
          "volume" => 3,
          "year_began" => 2016,
          "series_type" => %{"id" => 1, "name" => "Ongoing Series"},
          "language" => "en",
          "genres" => [%{"id" => 1, "name" => "Super-Hero"}]
        },
        "number" => "1",
        "alt_number" => "",
        "title" => "",
        "name" => ["I Am Gotham, Part One"],
        "cover_date" => "2016-08-01",
        "store_date" => "2016-06-15",
        "price" => "2.99",
        "price_currency" => "USD",
        "rating" => %{"id" => 2, "name" => "Teen"},
        "sku" => "",
        "isbn" => "",
        "upc" => "76194134182900111",
        "page" => 32,
        "desc" => "Batman meets Gotham.",
        "image" => "https://static.metron.cloud/cover.jpg",
        "arcs" => [%{"id" => 7, "name" => "I Am Gotham"}],
        "credits" => [
          %{"id" => 1, "creator" => "Tom King", "role" => [%{"id" => 1, "name" => "Writer"}]},
          %{
            "id" => 2,
            "creator" => "David Finch",
            "role" => [%{"id" => 2, "name" => "Penciller"}, %{"id" => 3, "name" => "Cover"}]
          },
          %{"id" => 3, "creator" => "Odd Person", "role" => [%{"id" => 99, "name" => "Some Future Role"}]}
        ],
        "characters" => [%{"id" => 10, "name" => "Batman"}],
        "teams" => [],
        "universes" => [],
        "reprints" => [],
        "variants" => [],
        "cv_id" => 540_000,
        "gcd_id" => nil,
        "resource_url" => "https://metron.cloud/issue/batman-2016-1/"
      },
      overrides
    )
  end

  def metron_series_list(results), do: %{"count" => length(results), "next" => nil, "results" => results}

  def metron_series_item(id, name, year),
    do: %{"id" => id, "series" => "#{name} (#{year})", "year_began" => year, "issue_count" => 50, "volume" => 1}

  def metron_issue_item(id, series_id, series_name, number, cover_date) do
    %{
      "id" => id,
      "series" => %{"id" => series_id, "name" => series_name, "volume" => 1, "year_began" => 2016},
      "number" => number,
      "issue" => "#{series_name} ##{number}",
      "cover_date" => cover_date,
      "image" => "https://static.metron.cloud/#{id}.jpg"
    }
  end

  @doc "Enables and configures the Metron source."
  def enable_metron!(attrs \\ %{}) do
    %{config: row} = Sources.get("metron")

    {:ok, row} = Sources.update(row, Map.merge(%{"config" => %{"username" => "u", "password" => "p"}}, attrs))
    {:ok, row} = Sources.update(row, %{"last_test_status" => "ok"})
    {:ok, row} = Sources.set_enabled(row, true)
    row
  end

  def library_fixture(tmp) do
    {:ok, lib} = Library.create_library(%{name: "Lib #{System.unique_integer([:positive])}", root_path: tmp})
    lib
  end

  def series_fixture(lib, attrs \\ %{}) do
    {:ok, s} =
      Library.create_or_find_series(
        Map.merge(
          %{library_id: lib.id, name: "Batman", start_year: 2016, path: Path.join(lib.root_path, "Batman")},
          attrs
        )
      )

    s
  end

  def book_fixture(lib, series, attrs \\ %{}) do
    {:ok, b} =
      Library.create_book(
        Map.merge(
          %{
            library_id: lib.id,
            series_id: series && series.id,
            title: "Batman 001",
            issue_number: Decimal.new(1),
            year: 2016,
            page_count: 24
          },
          attrs
        )
      )

    # Record (not an actual file) so filename-derived titles are recognisable.
    dir = (series && series.path) || lib.root_path

    {:ok, _} =
      Library.create_book_file(%{
        book_id: b.id,
        path: Path.join(dir, "#{b.title}.cbz"),
        format: :cbz,
        file_size: 1,
        file_hash: "fixture-#{b.id}",
        last_modified: ~N[2024-01-01 00:00:00]
      })

    b
  end

  @doc "Creates a minimal CBZ with a few fake page entries."
  def cbz_fixture(path, extra \\ []) do
    files =
      [
        {~c"001.jpg", "page-one"},
        {~c"002.jpg", "page-two"},
        {~c"sub/003.png", "page-three"}
      ] ++ extra

    {:ok, _} = :zip.create(String.to_charlist(path), files)
    path
  end
end
