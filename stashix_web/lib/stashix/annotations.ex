# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Annotations do
  @moduledoc """
  Highlights, notes and bookmarks (`Stashix.Library.Annotation`). Each is a
  user's own: every call is scoped to the user, and making one also needs
  the book to be visible through `Stashix.Library.Access`.

  An image region (an `"image"` locator with a `"rect"`) also gets a
  cropped picture of the area, cut from the page when it is made and kept
  under `annotation_dir` (default: `annotations/` next to the thumbnails).
  """

  import Ecto.Query

  alias Stashix.Library.{Access, Annotation, Book, Locator}
  alias Stashix.Media.Extractor
  alias Stashix.{Library, Repo}

  require Logger

  @preview_width 600

  @doc "A user's annotations in a book, in book order."
  def list(user_id, book_id) do
    from(a in Annotation,
      where: a.user_id == ^user_id and a.book_id == ^book_id,
      order_by: [asc: a.progression, asc: a.inserted_at]
    )
    |> Repo.all()
  end

  @doc "How many annotations a user has in a book."
  def count(user_id, book_id) do
    Repo.aggregate(from(a in Annotation, where: a.user_id == ^user_id and a.book_id == ^book_id), :count)
  end

  def get(user_id, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %Annotation{} = a <- Repo.get_by(Annotation, id: id, user_id: user_id) do
      a
    else
      _ -> nil
    end
  end

  @doc """
  Makes an annotation from client params: `"kind"`, `"locator"` (see
  `Stashix.Library.Locator`), `"progression"`, `"color"`, `"text"`,
  `"note"`. `book_file` is the file being read, for image regions' crops.
  """
  def create(%Access{} = access, user_id, %Book{} = book, params, book_file \\ nil) do
    with true <- Repo.exists?(from(b in Access.books(access), where: b.id == ^book.id)) || {:error, :not_found},
         %{} = locator <- Locator.from_params(params["locator"]) || {:error, :bad_locator} do
      attrs = %{
        kind: params["kind"],
        color: params["color"],
        locator: locator,
        progression: progression(params["progression"]),
        text: params["text"],
        note: params["note"],
        user_id: user_id,
        book_id: book.id,
        book_file_id: book_file && book_file.id
      }

      with {:ok, annotation} <- %Annotation{} |> Annotation.create_changeset(attrs) |> Repo.insert() do
        {:ok, put_preview(annotation, book_file)}
      end
    end
  end

  def update(user_id, id, params) do
    case get(user_id, id) do
      nil -> {:error, :not_found}
      a -> a |> Annotation.update_changeset(Map.take(params, ["color", "note"])) |> Repo.update()
    end
  end

  def delete(user_id, id) do
    case get(user_id, id) do
      nil ->
        {:error, :not_found}

      a ->
        with {:ok, a} <- Repo.delete(a) do
          if a.preview, do: File.rm(preview_path(a))
          {:ok, a}
        end
    end
  end

  defp progression(n) when is_number(n), do: n |> max(0) |> min(1) |> Kernel.*(1.0)
  defp progression(_), do: 0.0

  ## Region previews

  def preview_dir do
    Application.get_env(:stashix, :annotation_dir) ||
      Path.join(Path.dirname(Application.get_env(:stashix, :thumbnail_dir, "/tmp/stashix/thumbnails")), "annotations")
  end

  def preview_path(%Annotation{preview: name}) when is_binary(name), do: Path.join(preview_dir(), name)
  def preview_path(_), do: nil

  defp put_preview(%Annotation{locator: %{"type" => "image", "page" => page, "rect" => rect}} = a, %{path: path})
       when is_integer(page) do
    with {:ok, data} <- Extractor.get_page(path, page),
         {:ok, image} <- Image.from_binary(data),
         {:ok, crop} <- crop(image, rect),
         {:ok, small} <- Image.thumbnail(crop, @preview_width, resize: :down),
         name = "#{a.id}.jpg",
         :ok <- File.mkdir_p(preview_dir()),
         {:ok, _} <- Image.write(small, Path.join(preview_dir(), name), quality: 85),
         {:ok, a} <- a |> Ecto.Changeset.change(preview: name) |> Repo.update() do
      a
    else
      error ->
        Logger.warning("Annotation preview failed for #{a.id}: #{inspect(error)}")
        a
    end
  end

  defp put_preview(a, _book_file), do: a

  defp crop(image, [x, y, w, h]) do
    {width, height, _} = Image.shape(image)
    left = round(x * width)
    top = round(y * height)

    Image.crop(
      image,
      left,
      top,
      max(min(round(w * width), width - left), 1),
      max(min(round(h * height), height - top), 1)
    )
  end

  ## Export

  @doc "The annotations as Markdown: quotes, notes and where they are."
  def to_markdown(%Book{} = book, annotations) do
    header = "# #{book.title}\n\n"

    body =
      Enum.map_join(annotations, "\n", fn a ->
        where = where(a)
        quote_ = a.text && Enum.map_join(String.split(a.text, "\n"), "\n", &"> #{&1}")

        [
          "## #{kind_label(a.kind)}#{where && " — #{where}"}",
          quote_,
          a.note,
          a.preview && "_(picture of the marked area)_"
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")
        |> Kernel.<>("\n")
      end)

    header <> body
  end

  @doc "The annotations as JSON-ready maps (no internal ids beyond the annotation's)."
  def to_export(%Book{} = book, annotations) do
    %{
      book: %{id: book.id, title: book.title},
      annotations:
        Enum.map(annotations, fn a ->
          %{
            id: a.id,
            kind: a.kind,
            color: a.color,
            text: a.text,
            note: a.note,
            locator: a.locator,
            progression: a.progression,
            created_at: a.inserted_at,
            updated_at: a.updated_at
          }
        end)
    }
  end

  defp kind_label(:highlight), do: "Highlight"
  defp kind_label(:note), do: "Note"
  defp kind_label(:bookmark), do: "Bookmark"

  defp where(%{locator: %{"page" => page}}) when is_integer(page), do: "page #{page + 1}"
  defp where(%{progression: p}) when p > 0, do: "#{round(p * 100)}%"
  defp where(_), do: nil

  @doc "The file being read for a book, to cut region previews from."
  def book_file(book, format), do: Library.get_preferred_book_file(book, format)
end
