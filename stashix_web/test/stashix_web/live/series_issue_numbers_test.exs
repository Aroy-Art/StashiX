# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SeriesIssueNumbersTest do
  use StashixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Stashix.{Accounts, Library, Repo}
  alias Stashix.Library.Book
  alias Stashix.Auth.TokenHelper

  @root "/tmp/comics-issue-numbers/The Fox and the Crow (1952-1968)"

  setup %{conn: conn} do
    {:ok, admin} =
      Accounts.create_user(%{email: "a@example.com", username: "adm", password: "password1234", role: :admin})

    {:ok, access, refresh} = TokenHelper.generate_tokens(admin)
    conn = Plug.Test.init_test_session(conn, %{"guardian_default_token" => access, "guardian_refresh_token" => refresh})

    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: "/tmp/comics-issue-numbers"})
    {:ok, series} = Library.create_or_find_series(%{library_id: lib.id, name: "The Fox and the Crow", path: @root})

    book = fn file, number, attrs ->
      {:ok, book} =
        Library.create_book(
          Map.merge(%{library_id: lib.id, series_id: series.id, title: file, issue_number: number}, attrs)
        )

      {:ok, _} = Library.create_book_file(%{book_id: book.id, path: Path.join(@root, file), format: :cbz})
      book
    end

    %{
      conn: conn,
      series: series,
      wrong5: book.("The Fox and the Crow 005 ctc.cbz", 1, %{}),
      wrong92: book.("The Fox and the Crow 092 ctc.cbz", 1, %{}),
      right: book.("The Fox and the Crow 007 ctc.cbz", 7, %{}),
      locked: book.("The Fox and the Crow 010 ctc.cbz", 1, %{locked_fields: ["issue_number"]}),
      unparsed: book.("Annual Special.cbz", 3, %{})
    }
  end

  defp number(book), do: Repo.get!(Book, book.id).issue_number

  test "preview lists only issues that differ from their file name", %{series: series} = ctx do
    preview = Library.filename_issue_numbers_preview(series.id)

    assert Enum.map(preview.affected, &{&1.book.id, Decimal.to_string(&1.to)}) == [
             {ctx.wrong5.id, "5"},
             {ctx.wrong92.id, "92"}
           ]

    assert preview.unchanged == 1
    assert preview.unparsed == 1
  end

  test "dialog updates the ticked issues only", %{conn: conn, series: series} = ctx do
    {:ok, view, _} = live_canonical(conn, ~p"/series/#{series.id}")

    view |> element("[phx-click=open_issue_numbers_dialog]") |> render_click()
    assert render(view) =~ "2 of 4 issues differ"
    assert render(view) =~ "Update 2 issues"

    view |> element("#issue-numbers-dialog input[phx-value-id='#{ctx.wrong92.id}']") |> render_click()
    assert render(view) =~ "Update 1 issue"

    view |> element("#issue-numbers-dialog button[phx-click=apply_issue_numbers]") |> render_click()
    refute has_element?(view, "#issue-numbers-dialog")

    assert Decimal.equal?(number(ctx.wrong5), 5)
    assert Decimal.equal?(number(ctx.wrong92), 1)
    assert Decimal.equal?(number(ctx.locked), 1)
    assert Decimal.equal?(number(ctx.unparsed), 3)
  end
end
