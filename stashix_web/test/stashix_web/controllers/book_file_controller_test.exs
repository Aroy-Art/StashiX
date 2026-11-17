# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.BookFileControllerTest do
  use StashixWeb.ConnCase, async: false

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Auth.TokenHelper
  alias Stashix.Library.BookFile
  alias StashixWeb.BookFileController

  @moduletag :tmp_dir

  # 0..255, so every byte says where it came from.
  @data :binary.list_to_bin(Enum.to_list(0..255))

  setup %{conn: conn, tmp_dir: tmp} do
    {:ok, user} = Accounts.create_user(%{email: "r@example.com", username: "reader", password: "password1234"})
    {:ok, access, refresh} = TokenHelper.generate_tokens(user)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Books", root_path: tmp})

    # Reading only: the text reader must work without download permission.
    {:ok, _} =
      Library.set_library_permission(%{user_id: user.id, library_id: lib.id, can_read: true, max_age_rating: :adult})

    book = fn title, kind ->
      {:ok, b} = Library.create_book(%{title: title, library_id: lib.id})
      path = Path.join(tmp, "#{title}.pdf")
      File.write!(path, @data)
      Repo.insert!(%BookFile{book_id: b.id, path: path, format: :pdf, file_size: 256, content_kind: kind})
      b
    end

    %{conn: conn, text: book.("Novel", :text), scan: book.("Scan", :images)}
  end

  defp get_file(conn, book, range \\ nil) do
    conn = if range, do: put_req_header(conn, "range", range), else: conn
    get(conn, ~p"/api/books/#{book.id}/file")
  end

  test "sends the whole file without a Range", %{conn: conn, text: book} do
    conn = get_file(conn, book)
    assert conn.status == 200
    assert conn.resp_body == @data
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert ["application/pdf"] = get_resp_header(conn, "content-type")
  end

  test "sends one range as 206", %{conn: conn, text: book} do
    conn = get_file(conn, book, "bytes=10-19")
    assert conn.status == 206
    assert conn.resp_body == binary_part(@data, 10, 10)
    assert get_resp_header(conn, "content-range") == ["bytes 10-19/256"]
  end

  test "open-ended and suffix ranges", %{conn: conn, text: book} do
    assert get_file(conn, book, "bytes=250-").resp_body == binary_part(@data, 250, 6)
    assert get_file(conn, book, "bytes=-4").resp_body == binary_part(@data, 252, 4)
  end

  test "a range past the end is 416", %{conn: conn, text: book} do
    conn = get_file(conn, book, "bytes=300-400")
    assert conn.status == 416
    assert get_resp_header(conn, "content-range") == ["bytes */256"]
  end

  test "an override to text opens the file", %{conn: conn, scan: book} do
    {:ok, book} = Library.update_book(book, %{content_kind: :text})
    assert get_file(conn, book).status == 200
  end

  test "books that open as pages are forbidden", %{conn: conn, scan: scan, text: text} do
    assert get_file(conn, scan).status == 403

    {:ok, text} = Library.update_book(text, %{content_kind: :images})
    assert get_file(conn, text).status == 403
  end

  describe "parse_range/2" do
    test "clamps the end to the file" do
      assert BookFileController.parse_range("bytes=0-999", 100) == {:ok, 0, 99}
    end

    test "a suffix longer than the file is the whole file" do
      assert BookFileController.parse_range("bytes=-500", 100) == {:ok, 0, 99}
    end

    test "zero-length suffix and empty files are unsatisfiable" do
      assert BookFileController.parse_range("bytes=-0", 100) == :unsatisfiable
      assert BookFileController.parse_range("bytes=0-", 0) == :unsatisfiable
    end

    test "several ranges, reversed ranges and junk are ignored" do
      for header <- ["bytes=0-1,5-6", "bytes=9-3", "bytes=a-b", "items=0-1", "bytes=-"],
          do: assert(BookFileController.parse_range(header, 100) == :ignore)
    end
  end
end
