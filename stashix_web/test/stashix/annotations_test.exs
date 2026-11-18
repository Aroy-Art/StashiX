# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.AnnotationsTest do
  use Stashix.DataCase, async: false

  alias Stashix.{Accounts, Annotations, Library}
  alias Stashix.Library.{Access, BookFile, Locator}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Application.put_env(:stashix, :annotation_dir, Path.join(tmp, "annotations"))
    on_exit(fn -> Application.delete_env(:stashix, :annotation_dir) end)

    {:ok, user} = Accounts.create_user(%{email: "a@example.com", username: "annotator", password: "password1234"})
    {:ok, other} = Accounts.create_user(%{email: "b@example.com", username: "other", password: "password1234"})
    {:ok, lib} = Library.create_library(%{name: "Comics", root_path: tmp})
    {:ok, book} = Library.create_book(%{title: "Saga 001", library_id: lib.id, page_count: 1})

    page = Image.new!(200, 100, color: :blue) |> Image.write!(:memory, suffix: ".jpg")
    path = Path.join(tmp, "Saga 001.cbz")
    {:ok, _} = :zip.create(String.to_charlist(path), [{~c"001.jpg", page}])
    file = Repo.insert!(%BookFile{book_id: book.id, path: path, format: :cbz, file_size: 1, content_kind: :images})

    %{user: user, other: other, book: book, book_file: file, access: Access.all()}
  end

  test "a text highlight, listed in book order, changed and deleted", %{
    user: user,
    other: other,
    book: book,
    access: access
  } do
    params = fn cfi, p ->
      %{
        "kind" => "highlight",
        "color" => "yellow",
        "locator" => %{"type" => "epub", "cfi" => cfi, "evil" => true},
        "progression" => p,
        "text" => "Call me Ishmael."
      }
    end

    {:ok, later} = Annotations.create(access, user.id, book, params.("epubcfi(/6/8!/4/2,/1:0,/1:16)", 0.6))
    {:ok, early} = Annotations.create(access, user.id, book, params.("epubcfi(/6/4!/4/2,/1:0,/1:16)", 0.1))
    assert later.locator == %{"type" => "epub", "cfi" => "epubcfi(/6/8!/4/2,/1:0,/1:16)"}

    assert [%{id: id1}, %{id: id2}] = Annotations.list(user.id, book.id)
    assert {id1, id2} == {early.id, later.id}
    assert Annotations.list(other.id, book.id) == []

    assert {:error, :not_found} = Annotations.update(other.id, early.id, %{"note" => "mine now"})
    {:ok, a} = Annotations.update(user.id, early.id, %{"note" => "Opening line", "color" => "pink", "text" => "x"})
    assert {a.note, a.color, a.text} == {"Opening line", "pink", "Call me Ishmael."}
    assert {:error, %Ecto.Changeset{}} = Annotations.update(user.id, early.id, %{"color" => "plaid"})

    assert {:error, :not_found} = Annotations.delete(other.id, early.id)
    assert {:ok, _} = Annotations.delete(user.id, early.id)
    assert Annotations.count(user.id, book.id) == 1
  end

  test "an image region keeps a cropped picture of the area", ctx do
    %{user: user, book: book, book_file: file, access: access} = ctx
    locator = %{"type" => "image", "page" => 0, "rect" => [0.25, 0.5, 0.5, 0.5]}

    {:ok, a} =
      Annotations.create(
        access,
        user.id,
        book,
        %{"kind" => "highlight", "color" => "green", "locator" => locator},
        file
      )

    assert a.preview == "#{a.id}.jpg"
    assert {:ok, img} = Image.open(Annotations.preview_path(a))
    assert {100, 50, _} = Image.shape(img)

    {:ok, _} = Annotations.delete(user.id, a.id)
    refute File.exists?(Annotations.preview_path(a))
  end

  test "a book the user can't see takes no annotations", %{user: user, book: book} do
    params = %{"kind" => "bookmark", "locator" => %{"type" => "image", "page" => 0}}
    assert {:error, :not_found} = Annotations.create(Access.for_user(user), user.id, book, params)
    assert {:error, :bad_locator} = Annotations.create(Access.all(), user.id, book, Map.put(params, "locator", %{}))
  end

  test "export as Markdown and JSON", %{user: user, book: book, access: access} do
    {:ok, _} =
      Annotations.create(access, user.id, book, %{
        "kind" => "note",
        "locator" => %{"type" => "pdf", "page" => 4, "rects" => [[0.1, 0.1, 0.5, 0.02]]},
        "text" => "line one\nline two",
        "note" => "Remember this"
      })

    {:ok, _} =
      Annotations.create(access, user.id, book, %{"kind" => "bookmark", "locator" => %{"type" => "image", "page" => 0}})

    md = Annotations.to_markdown(book, Annotations.list(user.id, book.id))
    assert md =~ "# Saga 001"
    assert md =~ "## Note — page 5\n\n> line one\n> line two\n\nRemember this"
    assert md =~ "## Bookmark — page 1"

    assert %{book: %{title: "Saga 001"}, annotations: [_, _]} =
             Annotations.to_export(book, Annotations.list(user.id, book.id))
  end

  test "locator rects are clamped to the page" do
    assert Locator.rect([0.9, -0.2, 0.5, 0.5]) == [0.9, 0.0, 0.1, 0.5]
    assert Locator.rect([0.5, 0.5, 0, 0.2]) == nil

    assert Locator.from_params(%{"type" => "pdf", "page" => 1, "rects" => [[0, 0, 1, 1], "x"]}) == %{
             "type" => "pdf",
             "page" => 1
           }
  end
end
