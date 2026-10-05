defmodule StashixWeb.AccessLiveTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library}
  alias Stashix.Auth.TokenHelper

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "kid@example.com", username: "kid", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)

    conn =
      Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics"})

    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, max_age_rating: :teen})

    book = fn attrs ->
      {:ok, b} = Library.create_book(Map.merge(%{library_id: lib.id, type: "standalone"}, attrs))
      b
    end

    %{
      conn: conn,
      teen: book.(%{title: "Teen Tales", age_rating: :teen}),
      adult: book.(%{title: "Grown Up Stories", age_rating: :adult})
    }
  end

  test "lists and search leave out books above the limit", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/books")
    assert html =~ "Teen Tales"
    refute html =~ "Grown Up Stories"

    {:ok, _view, html} = live(conn, ~p"/search?q=stories")
    refute html =~ "Grown Up Stories"
  end

  test "direct links to hidden books 404", %{conn: conn, teen: teen, adult: adult} do
    {:ok, _view, html} = live(conn, ~p"/book/#{teen.id}")
    assert html =~ "Teen Tales"

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/book/#{adult.id}") end
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/read/#{adult.id}") end

    assert_error_sent 404, fn -> get(conn, ~p"/api/books/#{adult.id}/cover") end
  end

  test "metadata edits and rescans from non-admins are ignored", %{conn: conn, teen: teen} do
    {:ok, view, _html} = live(conn, ~p"/book/#{teen.id}")

    render_hook(view, "save_metadata", %{"book" => %{"age_rating" => "everyone", "title" => "Hacked"}})
    render_hook(view, "toggle_metadata_lock", %{})

    book = Library.get_book!(teen.id)
    assert book.title == "Teen Tales"
    assert book.age_rating == :teen
    refute book.metadata_locked
  end

  test "library management API is admin-only", %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "api@example.com", username: "apiuser", password: "password1234"})
    {:ok, token, _refresh} = TokenHelper.generate_tokens(user)
    conn = put_req_header(conn, "authorization", "Bearer " <> token)

    assert json_response(post(conn, ~p"/api/libraries", %{name: "X", root_path: "/tmp/x"}), 403)
    assert json_response(get(conn, ~p"/api/libraries"), 200)
  end

  test "library API hides server paths from non-admins", %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "api@example.com", username: "apiuser", password: "password1234"})

    {:ok, admin} =
      Accounts.create_user(%{email: "a@example.com", username: "adm", password: "password1234", role: :admin})

    [lib] = Library.list_libraries(admin)
    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})

    libraries = fn account ->
      {:ok, token, _refresh} = TokenHelper.generate_tokens(account)
      conn = put_req_header(conn, "authorization", "Bearer " <> token)
      json_response(get(conn, ~p"/api/libraries"), 200)["libraries"]
    end

    assert [%{"root_path" => "/tmp/comics"}] = libraries.(admin)
    assert [%{"name" => "Comics"} = seen] = libraries.(user)
    refute Map.has_key?(seen, "root_path")
  end

  test "permission changes disconnect the user's live sockets", %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "api@example.com", username: "apiuser", password: "password1234"})

    {:ok, admin} =
      Accounts.create_user(%{email: "a@example.com", username: "adm", password: "password1234", role: :admin})

    [lib] = Library.list_libraries(admin)
    Phoenix.PubSub.subscribe(Stashix.PubSub, Accounts.session_topic(user.id))

    {:ok, _} = Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true})
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    {:ok, _} = Accounts.update_user(user, %{password: "another-password"})
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    conn = post(conn, ~p"/login", %{"login" => "apiuser", "password" => "another-password"})
    assert get_session(conn, :live_socket_id) == Accounts.session_topic(user.id)
  end

  test "refresh tokens are not accepted as access tokens", %{conn: conn} do
    {:ok, user} = Accounts.create_user(%{email: "api@example.com", username: "apiuser", password: "password1234"})
    {:ok, _access, refresh} = TokenHelper.generate_tokens(user)

    assert {:error, _} = TokenHelper.resource_from_token(refresh)

    conn = put_req_header(conn, "authorization", "Bearer " <> refresh)
    assert json_response(get(conn, ~p"/api/libraries"), 401)
  end

  test "logout drops the whole session", %{conn: conn} do
    conn = delete(conn, ~p"/logout")
    assert redirected_to(conn) == "/login"

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end
end
