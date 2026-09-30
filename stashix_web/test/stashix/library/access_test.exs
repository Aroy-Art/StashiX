defmodule Stashix.Library.AccessTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Accounts, Library}
  alias Stashix.Library.{Access, Series}

  setup do
    {:ok, admin} =
      Accounts.create_user(%{email: "admin@example.com", username: "admin", password: "password1234", role: :admin})

    {:ok, user} = Accounts.create_user(%{email: "kid@example.com", username: "kid", password: "password1234"})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})
    {:ok, other} = Library.create_library(%{name: "Other", root_path: "/tmp/other"})

    series = fn name -> Repo.insert!(Series.changeset(%Series{}, %{name: name, library_id: lib.id})) end
    kids = series.("Kids Series")
    grown = series.("Grown Series")
    mixed = series.("Mixed Series")

    book = fn attrs ->
      {:ok, b} = Library.create_book(Map.merge(%{library_id: lib.id, type: "issue"}, attrs))
      b
    end

    books = %{
      everyone: book.(%{title: "Everyone", age_rating: :everyone, series_id: kids.id, issue_number: 1}),
      teen_plus: book.(%{title: "Teen Plus", age_rating: :teen_plus, series_id: mixed.id, issue_number: 1}),
      mature: book.(%{title: "Mature", age_rating: :mature, series_id: grown.id, issue_number: 1}),
      mature_mixed: book.(%{title: "Mature Mixed", age_rating: :mature, series_id: mixed.id, issue_number: 2}),
      unrated: book.(%{title: "Unrated", age_rating: :unknown, type: "standalone"}),
      other: book.(%{title: "Other Lib", library_id: other.id, age_rating: :everyone, type: "standalone"})
    }

    %{admin: admin, user: user, lib: lib, other: other, books: books, kids: kids, grown: grown, mixed: mixed}
  end

  defp permit(user, lib, attrs) do
    {:ok, _} =
      Library.set_library_permission(Map.merge(%{user_id: user.id, library_id: lib.id, can_read: true}, attrs))

    Access.for_user(user)
  end

  defp titles(access) do
    Library.list_all_books(access: access, limit: 100) |> Enum.map(& &1.title) |> Enum.sort()
  end

  defp series_names(access) do
    Library.list_all_series(access: access, limit: 100) |> Enum.map(& &1.name) |> Enum.sort()
  end

  test "admins see everything", %{admin: admin} do
    access = Access.for_user(admin)
    assert length(titles(access)) == 6
    assert series_names(access) == ["Grown Series", "Kids Series", "Mixed Series"]
  end

  test "users without permissions see nothing", %{user: user} do
    assert titles(Access.for_user(user)) == []
    assert series_names(Access.for_user(user)) == []
  end

  test "age limit hides higher-rated books and series with none left", %{user: user, lib: lib} do
    access = permit(user, lib, %{max_age_rating: :teen_plus})

    assert titles(access) == ["Everyone", "Teen Plus", "Unrated"]
    assert series_names(access) == ["Kids Series", "Mixed Series"]
    assert Library.count_all_books(access: access) == 3
  end

  test "hide_unrated hides unrated books under a limit", %{user: user, lib: lib} do
    access = permit(user, lib, %{max_age_rating: :teen_plus, hide_unrated: true})
    assert titles(access) == ["Everyone", "Teen Plus"]
  end

  test "no age limit shows every rating in the library", %{user: user, lib: lib} do
    access = permit(user, lib, %{max_age_rating: :unknown, hide_unrated: true})
    assert titles(access) == ["Everyone", "Mature", "Mature Mixed", "Teen Plus", "Unrated"]
  end

  test "can_read false hides the library", %{user: user, lib: lib} do
    access = permit(user, lib, %{max_age_rating: :unknown, can_read: false})
    assert titles(access) == []
  end

  test "single fetches raise for hidden items", %{user: user, lib: lib, other: other} = ctx do
    access = permit(user, lib, %{max_age_rating: :teen_plus})

    assert Library.get_book_with_series(access, ctx.books.everyone.id)
    assert_raise Ecto.NoResultsError, fn -> Library.get_book!(access, ctx.books.mature.id) end
    assert_raise Ecto.NoResultsError, fn -> Library.get_book!(access, ctx.books.other.id) end
    assert_raise Ecto.NoResultsError, fn -> Library.get_series_with_books(access, ctx.grown.id) end
    assert_raise Ecto.NoResultsError, fn -> Library.get_readable_library!(access, other.id) end

    mixed = Library.get_series_with_books(access, ctx.mixed.id)
    assert Enum.map(mixed.books, & &1.title) == ["Teen Plus"]
    assert {nil, nil} = Library.get_adjacent_books(access, ctx.books.teen_plus)
  end

  test "search and counts respect access", %{user: user, lib: lib} do
    access = permit(user, lib, %{max_age_rating: :teen_plus})

    %{issues: issues, series: series} = Library.search_all("mature", access: access)
    assert issues == []
    assert series == []

    {books, total} = Library.search_filtered_books(%{types: ["issue", "standalone"]}, access: access)
    assert total == 3
    assert length(books) == 3

    {series, _} = Library.search_filtered_series(%{}, access: access)
    assert [%{name: "Mixed Series", issue_count: 1}, %{name: "Kids Series"}] = Enum.sort_by(series, & &1.name, :desc)

    assert Library.count_issues(access, lib.id) == 2
    assert Library.count_series(access, lib.id) == 2

    assert Library.stats_books_by_age_rating(access) |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
             [:everyone, :teen_plus, :unknown]
  end

  test "publishers only show when they have visible books or series", %{user: user, lib: lib} = ctx do
    access = permit(user, lib, %{max_age_rating: :teen_plus})

    {:ok, kids_pub} = Library.get_or_create_publisher("Kids Press")
    {:ok, adult_pub} = Library.get_or_create_publisher("Adult Press")
    {:ok, alias_pub} = Library.get_or_create_publisher("Kids Press Imprint")
    {:ok, _} = Library.set_publisher_alias(alias_pub.id, kids_pub.id)

    Library.link_publisher_to_book(ctx.books.everyone.id, alias_pub.id)
    Library.link_publisher_to_book(ctx.books.mature.id, adult_pub.id)

    assert Enum.map(Library.list_publishers(access), & &1.name) == ["Kids Press"]
    assert Library.count_publishers(access) == 1
    assert Library.get_publisher_with_aliases!(access, kids_pub.id)
    assert_raise Ecto.NoResultsError, fn -> Library.get_publisher_with_aliases!(access, adult_pub.id) end
    assert Library.count_publishers(Access.all()) == 2
  end

  test "progress can only be saved on visible books", %{user: user, lib: lib} = ctx do
    access = permit(user, lib, %{max_age_rating: :teen_plus})

    assert {:ok, _} = Library.update_progress(access, user.id, ctx.books.everyone.id, 3)
    assert {:error, :not_found} = Library.update_progress(access, user.id, ctx.books.mature.id, 3)
    assert Library.get_progress(user.id, ctx.books.mature.id) == nil
  end
end
