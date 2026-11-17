# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.ProgressTest do
  use Stashix.DataCase, async: true

  alias Stashix.{Accounts, Library}
  alias Stashix.Library.{Access, ReadingProgress}

  setup do
    {:ok, user} = Accounts.create_user(%{email: "p@example.com", username: "progress", password: "password1234"})
    {:ok, lib} = Library.create_library(%{name: "Books", root_path: "/tmp/progress"})

    book = fn title, pages ->
      {:ok, b} = Library.create_book(%{title: title, library_id: lib.id, page_count: pages})
      b
    end

    %{
      user: user,
      access: Access.all(),
      comic: book.("Comic", 11),
      novel: book.("Novel", 400),
      short: book.("Leaflet", 1)
    }
  end

  test "progression follows the page unless given", %{user: user, access: access, comic: comic, novel: novel} do
    {:ok, p} = Library.update_progress(access, user.id, comic.id, 5)
    assert p.progression == 0.5
    assert p.locator == nil

    locator = %{"type" => "epub", "cfi" => "epubcfi(/6/8!/4/2/1:0)", "href" => "OEBPS/ch3.xhtml"}
    {:ok, _} = Library.update_progress(access, user.id, novel.id, 40, progression: 0.12, locator: locator)

    p = Library.get_progress(user.id, novel.id)
    assert p.current_page == 40
    assert p.progression == 0.12
    assert p.locator == Map.put(locator, "progression", 0.12)
  end

  test "progression is clamped, and the last page is the end", %{user: user, access: access, comic: comic, short: short} do
    {:ok, p} = Library.update_progress(access, user.id, comic.id, 10)
    assert p.progression == 1.0

    {:ok, p} = Library.update_progress(access, user.id, comic.id, 3, progression: 7)
    assert p.progression == 1.0

    {:ok, p} = Library.update_progress(access, user.id, short.id, 0)
    assert p.progression == 0.0
  end

  test "status, continue reading and stats go by progression", ctx do
    %{user: user, access: access, comic: comic, novel: novel, short: short} = ctx

    # Location 399 of a 400-location EPUB is not the end until the reader says so.
    {:ok, _} = Library.update_progress(access, user.id, novel.id, 399, progression: 0.97)
    {:ok, _} = Library.update_progress(access, user.id, comic.id, 10)

    assert [%{book: %{id: id}, progression: 0.97}] = Library.in_progress_books(access, user.id)
    assert id == novel.id
    assert Library.progress_map(user.id, [comic.id, novel.id, short.id]) == %{comic.id => 1.0, novel.id => 0.97}

    status = fn s -> Library.search_filtered_books(%{read_status: s, user_id: user.id}, access: access) |> elem(0) end
    assert ids(status.("read")) == [comic.id]
    assert ids(status.("in_progress")) == [novel.id]
    assert ids(status.("unread")) == [short.id]

    assert %{in_progress: 1, completed: 1, unread: 1} = Library.stats_reading_progress(access, user.id)
  end

  test "client params keep only the locator's known fields" do
    params = %{
      "progression" => 0.4,
      "locator" => %{"type" => "epub", "cfi" => "epubcfi(/6/2!/4)", "href" => "a.xhtml", "evil" => "x", "page" => -1}
    }

    assert ReadingProgress.opts_from_params(params) == [
             locator: %{"type" => "epub", "cfi" => "epubcfi(/6/2!/4)", "href" => "a.xhtml"},
             progression: 0.4
           ]

    assert ReadingProgress.opts_from_params(%{"locator" => %{"type" => "html"}, "progression" => "1"}) == []

    assert ReadingProgress.opts_from_params(%{"locator" => %{"type" => "pdf", "cfi" => "javascript:"}}) ==
             [locator: %{"type" => "pdf"}]
  end

  defp ids(books), do: books |> Enum.map(& &1.id) |> Enum.sort()
end
