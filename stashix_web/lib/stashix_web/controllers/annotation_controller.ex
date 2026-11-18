# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.AnnotationController do
  @moduledoc """
  A user's annotations (`Stashix.Annotations`) outside the readers: the
  cropped picture of an image region, and a book's annotations exported as
  Markdown or JSON. Both only ever show the signed-in user's own.
  """
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.{Annotations, Library}
  alias StashixWeb.Schemas

  operation :preview,
    summary: "Picture of an image-region annotation",
    tags: ["Annotations"],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"JPEG", "image/jpeg", %OpenApiSpex.Schema{type: :string, format: :binary}},
      not_found: {"No such annotation or no picture", "application/json", Schemas.Error}
    ]

  def preview(conn, %{"id" => id}) do
    with %{id: user_id} <- conn.assigns[:current_user],
         %{preview: name} = a when is_binary(name) <- Annotations.get(user_id, id),
         path = Annotations.preview_path(a),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_file(200, path)
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not found"})
    end
  end

  operation :export,
    summary: "Export a book's annotations",
    description: "The signed-in user's highlights, notes and bookmarks in a book, as Markdown or JSON.",
    tags: ["Annotations"],
    parameters: [
      id: [in: :path, type: :string, required: true],
      format: [in: :query, type: :string, description: "md (default) or json"]
    ],
    responses: [
      ok: {"Annotations", "text/markdown", %OpenApiSpex.Schema{type: :string}},
      not_found: {"No such book", "application/json", Schemas.Error}
    ]

  def export(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    book = Library.get_book!(conn.assigns.access, id)
    annotations = Annotations.list(user.id, book.id)
    name = String.replace(book.title, ~r/[^\w\- ]+/u, "") |> String.trim() |> then(&if(&1 == "", do: "book", else: &1))

    case params["format"] do
      "json" ->
        conn
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{name} annotations.json"))
        |> json(Annotations.to_export(book, annotations))

      _ ->
        conn
        |> put_resp_content_type("text/markdown")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{name} annotations.md"))
        |> send_resp(200, Annotations.to_markdown(book, annotations))
    end
  end
end
