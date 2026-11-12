# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.SlugTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Library, Repo, Slug}
  alias Stashix.Library.{Book, Series}

  doctest Stashix.Slug

  @uuid "a7f3b2c9-1b04-4e1a-9c2f-8d6b5a0e1f23"

  describe "slugify/1" do
    test "lowercases, strips accents and collapses punctuation" do
      assert Slug.slugify("  Saga: Book One!! ") == "saga-book-one"
      assert Slug.slugify("Les Mauvaises Gens — Édition") == "les-mauvaises-gens-edition"
    end

    test "joins list parts, skipping nil and empty ones" do
      assert Slug.slugify(["Saga", nil, 2012, ""]) == "saga-2012"
    end

    test "is empty for text with nothing to keep" do
      assert Slug.slugify(nil) == ""
      assert Slug.slugify("進撃の巨人") == ""
    end

    test "caps the length without a trailing dash" do
      slug = Slug.slugify(String.duplicate("ab ", 40))
      assert String.length(slug) <= 60
      refute String.ends_with?(slug, "-")
    end
  end

  describe "to_param/2" do
    test "appends the short id" do
      assert Slug.to_param("Saga", @uuid) == "saga-a7f3b2c91b04"
    end

    test "is just the short id when the name slugs to nothing" do
      assert Slug.to_param("進撃の巨人", @uuid) == "a7f3b2c91b04"
    end
  end

  describe "parse/1" do
    test "accepts full UUIDs in any case" do
      assert Slug.parse(String.upcase(@uuid)) == {:uuid, @uuid}
    end

    test "turns a trailing short id into an inclusive UUID range" do
      lo = "a7f3b2c9-1b04-0000-0000-000000000000"
      hi = "a7f3b2c9-1b04-ffff-ffff-ffffffffffff"

      assert Slug.parse("saga-2012-a7f3b2c91b04") == {:range, lo, hi}
      assert Slug.parse("a7f3b2c91b04") == {:range, lo, hi}
    end

    test "rejects params without a usable id" do
      assert Slug.parse("saga") == :error
      assert Slug.parse("saga-a7f3b2c91b0") == :error
      assert Slug.parse("saga-xa7f3b2c91b04") == :error
      assert Slug.parse(nil) == :error
    end
  end

  describe "resolve/2" do
    setup do
      {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})
      %{lib: lib}
    end

    test "finds a row by slug, bare short id or full UUID", %{lib: lib} do
      series = Repo.insert!(%Series{name: "Saga", start_year: 2012, library_id: lib.id})
      param = Phoenix.Param.to_param(series)

      assert {:ok, series.id} == Slug.resolve(Series, param)
      assert {:ok, series.id} == Slug.resolve(Series, Slug.short(series.id))
      assert {:ok, series.id} == Slug.resolve(Series, "renamed-#{Slug.short(series.id)}")
      assert {:ok, series.id} == Slug.resolve(Series, series.id)
    end

    test "is scoped to the queried table", %{lib: lib} do
      series = Repo.insert!(%Series{name: "Saga", library_id: lib.id})
      assert Slug.resolve(Book, Phoenix.Param.to_param(series)) == :error
    end

    test "a short id shared by two rows is settled by the slug", %{lib: lib} do
      saga = Repo.insert!(%Series{id: "a7f3b2c9-1b04-4e1a-9c2f-8d6b5a0e1f23", name: "Saga", library_id: lib.id})
      paper = Repo.insert!(%Series{id: "a7f3b2c9-1b04-4f2b-8d3e-7c5a4b9f0e12", name: "Paper Girls", library_id: lib.id})

      assert Slug.resolve(Series, "saga-a7f3b2c91b04") == {:ok, saga.id}
      assert Slug.resolve(Series, "paper-girls-a7f3b2c91b04") == {:ok, paper.id}

      # Without a slug that matches either, there's no telling them apart...
      assert Slug.resolve(Series, "a7f3b2c91b04") == {:error, :ambiguous}
      assert Slug.resolve(Series, "old-name-a7f3b2c91b04") == {:error, :ambiguous}
      assert_raise Ecto.NoResultsError, fn -> Slug.resolve!(Series, "a7f3b2c91b04") end

      # ...but full UUIDs always work.
      assert Slug.resolve(Series, saga.id) == {:ok, saga.id}
    end

    test "colliding books match on their series slug or their title slug", %{lib: lib} do
      series = Repo.insert!(%Series{name: "Saga", start_year: 2012, library_id: lib.id})

      [one, two] =
        for {tail, n} <- [{"4e1a-9c2f-8d6b5a0e1f23", 1}, {"4f2b-8d3e-7c5a4b9f0e12", 2}] do
          Repo.insert!(%Book{
            id: "a7f3b2c9-1b04-#{tail}",
            library_id: lib.id,
            series_id: series.id,
            title: "Chapter #{n}",
            issue_number: Decimal.new(n)
          })
        end

      assert Slug.resolve(Book, "saga-2012-001-a7f3b2c91b04") == {:ok, one.id}
      assert Slug.resolve(Book, "saga-2012-002-a7f3b2c91b04") == {:ok, two.id}
      assert Slug.resolve(Book, "chapter-2-a7f3b2c91b04") == {:ok, two.id}
    end

    test "colliding rows with the same slug stay ambiguous", %{lib: lib} do
      for tail <- ["4e1a-9c2f-8d6b5a0e1f23", "4f2b-8d3e-7c5a4b9f0e12"] do
        Repo.insert!(%Series{id: "a7f3b2c9-1b04-#{tail}", name: "Saga", library_id: lib.id})
      end

      assert Slug.resolve(Series, "saga-a7f3b2c91b04") == {:error, :ambiguous}
    end

    test "raises a 404 for unknown or malformed params" do
      assert_raise Ecto.NoResultsError, fn -> Slug.resolve!(Series, "saga-000000000000") end
      assert_raise Ecto.NoResultsError, fn -> Slug.resolve!(Series, "saga") end
    end
  end

  describe "Phoenix.Param" do
    setup do
      {:ok, lib} = Library.create_library(%{name: "My Comics", root_path: "/tmp/comics"})
      series = Repo.insert!(%Series{name: "Saga", start_year: 2012, library_id: lib.id})
      %{lib: lib, series: series}
    end

    test "names issues after their series, year and padded number", %{lib: lib, series: series} do
      book = fn n ->
        {:ok, b} =
          Library.create_book(%{library_id: lib.id, series_id: series.id, type: "issue", title: "x", issue_number: n})

        Repo.preload(b, :series)
      end

      assert Phoenix.Param.to_param(book.(1)) =~ ~r/\Asaga-2012-001-[0-9a-f]{12}\z/
      assert Phoenix.Param.to_param(book.(Decimal.new("1.5"))) =~ ~r/\Asaga-2012-001-5-[0-9a-f]{12}\z/
      assert Phoenix.Param.to_param(book.(1234)) =~ ~r/\Asaga-2012-1234-[0-9a-f]{12}\z/
    end

    test "falls back to the title for standalone books and unloaded series", %{lib: lib, series: series} do
      {:ok, standalone} = Library.create_book(%{library_id: lib.id, type: "standalone", title: "Maus"})

      {:ok, issue} =
        Library.create_book(%{library_id: lib.id, series_id: series.id, title: "Saga 001", issue_number: 1})

      assert Phoenix.Param.to_param(standalone) =~ ~r/\Amaus-[0-9a-f]{12}\z/
      assert Phoenix.Param.to_param(issue) =~ ~r/\Asaga-001-[0-9a-f]{12}\z/
    end

    test "slugs libraries by name", %{lib: lib} do
      assert Phoenix.Param.to_param(lib) == "my-comics-" <> Slug.short(lib.id)
    end
  end
end
