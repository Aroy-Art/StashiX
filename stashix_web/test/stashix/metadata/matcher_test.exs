defmodule Stashix.Metadata.MatcherTest do
  use Stashix.DataCase, async: false

  import Stashix.MetadataFixtures

  alias Stashix.{Library, Metadata, Repo}
  alias Stashix.Library.{Book, BookExternalId, BookUrl, SeriesExternalId}
  alias Stashix.Metadata.{Candidate, Matcher, MatchReview}

  describe "scoring" do
    test "normalize_name ignores case, punctuation, leading 'The' and year suffix" do
      assert Matcher.normalize_name("The Amazing Spider-Man (2018)") == "amazing spider man"
    end

    test "normalize_number" do
      assert Matcher.normalize_number("001") == "1"
      assert Matcher.normalize_number("#1.0") == "1"
      assert Matcher.normalize_number("1.MU") == "1.mu"
    end

    test "exact issue scores high, wrong number scores low" do
      q = %{"series_name" => "Batman", "number" => "1", "year" => 2016, "publisher" => "DC Comics"}
      good = %Candidate{series_name: "Batman", number: "1", year: 2016, publisher: "DC Comics"}
      bad = %Candidate{series_name: "Batman", number: "2", year: 2016}

      assert Matcher.score_issue(good, q, 0.0) == 1.0
      assert Matcher.score_issue(bad, q, 0.0) < 0.75
    end

    test "confident? needs threshold and margin" do
      s = %{"auto_match_threshold" => 0.9, "auto_match_margin" => 0.1}
      assert Matcher.confident?([%Candidate{score: 0.95}], s)
      refute Matcher.confident?([%Candidate{score: 0.95}, %Candidate{score: 0.9}], s)
      refute Matcher.confident?([%Candidate{score: 0.8}], s)
    end
  end

  describe "identify_book/1" do
    setup do
      tmp = Path.join(System.tmp_dir!(), "stashix_meta_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      Stashix.Settings.put("metadata", %{"write_to_files" => false})
      lib = library_fixture(tmp)
      series = series_fixture(lib)
      %{lib: lib, series: series, book: book_fixture(lib, series)}
    end

    test "no enabled source", %{book: book} do
      assert Metadata.identify_book(book) == {:error, :no_sources}
    end

    test "confident match is applied", %{book: book, series: series} do
      enable_metron!()

      Req.Test.stub(Stashix.Metadata.HTTP, fn conn ->
        case conn.request_path do
          "/api/series/" ->
            Req.Test.json(conn, metron_series_list([metron_series_item(55, "Batman", 2016)]))

          "/api/issue/" ->
            assert conn.query_params["series_id"] == "55"
            assert conn.query_params["number"] == "1"
            Req.Test.json(conn, metron_series_list([metron_issue_item(111, 55, "Batman", "1", "2016-08-01")]))

          "/api/issue/111/" ->
            Req.Test.json(conn, metron_issue())
        end
      end)

      assert {:applied, _} = Metadata.identify_book(book)

      book =
        Repo.get!(Book, book.id)
        |> Repo.preload([:credits, :characters, :publishers, :external_ids, :story_arcs])

      assert book.title == "I Am Gotham, Part One"
      assert book.summary == "Batman meets Gotham."
      assert book.metadata_source == "metron"
      assert book.metadata_matched_at
      # page count from the file is kept, not replaced by the source's
      assert book.page_count == 24
      assert Enum.map(book.publishers, & &1.name) == ["DC Comics"]
      assert Enum.any?(book.credits, &(&1.role == :Other))
      assert Enum.any?(book.credits, &(&1.role == :"Cover Artist"))
      assert Enum.map(book.story_arcs, & &1.name) == ["I Am Gotham"]
      assert Enum.sort(Enum.map(book.external_ids, &to_string(&1.source))) == ["Comic Vine", "Metron"]

      assert Repo.get_by(SeriesExternalId, series_id: series.id, source: :Metron).source_id == "55"
      assert Library.get_series!(series.id).format == :"Single Issue"
    end

    test "known external id is fetched directly and other ids are kept", %{book: book} do
      enable_metron!()

      Repo.insert!(%BookExternalId{book_id: book.id, source: :Metron, source_id: "111"})
      Repo.insert!(%BookExternalId{book_id: book.id, source: :MangaDex, source_id: "zzz"})

      Req.Test.stub(Stashix.Metadata.HTTP, fn conn ->
        assert conn.request_path == "/api/issue/111/"
        Req.Test.json(conn, metron_issue())
      end)

      assert {:applied, _} = Metadata.identify_book(book)
      sources = Repo.all(from e in BookExternalId, where: e.book_id == ^book.id, select: e.source)
      assert :MangaDex in sources
    end

    test "ambiguous results create a review and applying one resolves it", %{book: book} do
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

      assert {:review, %MatchReview{} = review} = Metadata.identify_book(book)
      assert length(review.candidates) == 2
      assert Metadata.count_reviews() == 1

      [c | _] = Metadata.review_candidates(review)
      assert {:ok, _} = Metadata.apply_issue(book, c.source_key, c.id)
      assert Metadata.count_reviews() == 0
    end

    test "fill mode keeps existing values", %{book: book} do
      enable_metron!()
      Stashix.Settings.put("metadata", %{"write_to_files" => false, "overwrite_mode" => "fill"})
      {:ok, book} = Library.update_book(book, %{summary: "Mine"})

      Req.Test.stub(Stashix.Metadata.HTTP, fn conn -> Req.Test.json(conn, metron_issue()) end)
      assert {:ok, _} = Metadata.apply_issue(book, "metron", "111")

      book = Repo.get!(Book, book.id)
      assert book.summary == "Mine"
      assert book.upc == "76194134182900111"
    end

    test "explicit fields overwrite only what was chosen", %{book: book} do
      {:ok, book} = Library.update_book(book, %{summary: "Mine", upc: "000"})
      metadata = Stashix.MetadataFixtures.metron_issue() |> Stashix.Metadata.Sources.Metron.issue_metadata()

      assert {:ok, _} =
               Metadata.apply_issue_metadata(book, "metron", metadata, %{"write_to_files" => false},
                 fields: ["summary", "characters"]
               )

      book = Repo.get!(Book, book.id) |> Repo.preload([:characters, :credits])
      assert book.summary == "Batman meets Gotham."
      assert book.upc == "000"
      assert book.title == "Batman 001"
      assert Enum.map(book.characters, & &1.name) == ["Batman"]
      assert book.credits == []
    end

    test "links from another source are added, not replaced", %{book: book} do
      cv_url = "https://comicvine.gamespot.com/batman-1/4000-1/"
      Repo.insert!(%BookUrl{book_id: book.id, url: cv_url, is_primary: true})
      metron_url = "https://metron.cloud/issue/batman-2016-1/"
      metadata = %{summary: "Batman meets Gotham.", urls: [%{url: metron_url, is_primary: true}, %{url: cv_url}]}

      for opts <- [[], [fields: ["urls"]]], mode <- ["fill", "replace"] do
        settings = %{"write_to_files" => false, "overwrite_mode" => mode}
        assert {:ok, _} = Metadata.apply_issue_metadata(book, "metron", metadata, settings, opts)

        urls = Repo.all(from u in BookUrl, where: u.book_id == ^book.id, select: {u.url, u.is_primary})
        assert Enum.sort(urls) == Enum.sort([{cv_url, true}, {metron_url, false}])
      end
    end

    test "applying enqueues a file write when enabled", %{book: book} do
      Stashix.Settings.put("metadata", %{"write_to_files" => true})
      Req.Test.stub(Stashix.Metadata.HTTP, fn conn -> Req.Test.json(conn, metron_issue()) end)

      assert {:ok, _} = Metadata.apply_issue(book, "metron", "111")

      assert [%Oban.Job{args: %{"book_id" => id}}] =
               Repo.all(from j in Oban.Job, where: j.worker == "Stashix.Metadata.Workers.WriteFileWorker")

      assert id == book.id
    end
  end
end
