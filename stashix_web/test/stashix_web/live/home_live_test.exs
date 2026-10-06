defmodule StashixWeb.HomeLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{email: "home@example.com", username: "home", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})

    titles = for n <- 1..12, do: "Spotlight Candidate #{n}"
    for title <- titles, do: {:ok, _} = Library.create_book(%{library_id: lib.id, type: "standalone", title: title})

    %{conn: conn, user: user, lib: lib, titles: titles}
  end

  defp hero_title(html) do
    case Regex.run(~r/<h1[^>]*>\s*(.*?)\s*<\/h1>/s, html) do
      [_, title] -> title
      nil -> nil
    end
  end

  test "the random spotlight is picked once: not for the static page, and kept through a scan",
       %{conn: conn, lib: lib, titles: titles} do
    # Static render: a placeholder, no pick that the connected render would replace.
    static = conn |> get(~p"/") |> html_response(200)
    assert hero_title(static) == nil
    refute static =~ "Nothing on the shelves yet"

    {:ok, view, html} = live(conn, ~p"/")
    picked = hero_title(html)
    assert picked in titles

    # Books arriving during a scan must not reshuffle what is on screen.
    for n <- 1..5 do
      {:ok, book} = Library.create_book(%{library_id: lib.id, type: "standalone", title: "Late Arrival #{n}"})
      send(view.pid, {:book_added, book})
      assert hero_title(render(view)) == picked
    end
  end

  test "an empty library shows the welcome state once connected", %{conn: conn} do
    for book <- Library.list_all_books(access: Stashix.Library.Access.all(), limit: 100),
        do: Stashix.Repo.delete!(book)

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Nothing on the shelves yet"
  end
end
