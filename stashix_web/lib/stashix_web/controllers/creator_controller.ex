# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreatorController do
  use StashixWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Stashix.Library
  alias Stashix.Metadata.Roles
  alias StashixWeb.Schemas

  operation :show,
    summary: "Get a creator's work grouped by role",
    description:
      "Series (or books outside a series) the creator worked on, split into role groups " <>
        "(Writer, Artist, Colorist, Letterer, Cover, Editor, Translator, Other). " <>
        "Only books the caller may see are counted.",
    tags: ["Creators"],
    security: [%{"Bearer" => []}],
    parameters: [id: [in: :path, type: :string, description: "Creator ID", required: true]],
    responses: [
      ok: {"Creator works", "application/json", Schemas.CreatorWorks},
      unauthorized: {"Unauthorized", "application/json", Schemas.Error}
    ]

  def show(conn, %{"id" => id}) do
    creator = Library.get_creator!(id)
    works = Library.creator_works(conn.assigns.access, creator.id)

    groups =
      for heading <- Roles.headings(), list = works.groups[heading] do
        list = Enum.sort_by(list, &{-&1.count, &1.name})

        %{
          role_group: heading,
          book_count: Enum.sum(Enum.map(list, & &1.count)),
          works: Enum.map(list, &work_json/1)
        }
      end

    json(conn, %{
      creator: %{id: creator.id, name: creator.name},
      book_count: works.books,
      first_year: works.first_year,
      last_year: works.last_year,
      groups: groups
    })
  end

  defp work_json(work) do
    %{
      series_id: work.series_id,
      book_id: work.book_id,
      name: work.name,
      book_count: work.count,
      first_year: work.first_year,
      last_year: work.last_year,
      roles: work.roles
    }
  end
end
