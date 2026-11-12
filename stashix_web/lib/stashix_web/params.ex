# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

# Human-readable params for `~p"/series/#{series}"` and friends; the slugs
# themselves are built by `Stashix.Slug.param/1`. API routes keep passing `.id` and stay plain UUIDs.

for schema <- [
      Stashix.Library.Series,
      Stashix.Library.Book,
      Stashix.Library.Creator,
      Stashix.Library.Publisher,
      Stashix.Library.Library
    ] do
  defimpl Phoenix.Param, for: schema do
    def to_param(record), do: Stashix.Slug.param(record)
  end
end

defmodule StashixWeb.SlugParam do
  @moduledoc """
  Link params for records that may be schema structs or plain maps from a
  `select:` query, which `Phoenix.Param` refuses.
  """

  alias Stashix.Library.{Book, Series}
  alias Stashix.Slug

  @doc """
  The canonical param for a schema struct. A plain map is slugged from its
  `name` (plus `start_year`) or `title`; when that isn't the canonical form
  the page patches to it on arrival.
  """
  def slug_param(%_{} = record), do: Phoenix.Param.to_param(record)

  # Book maps that carry their series (e.g. adjacent issues) get the issue slug.
  def slug_param(%{id: _, issue_number: _, series: %Series{}} = book), do: Slug.param(struct(Book, book))

  def slug_param(%{id: id, name: name} = map), do: Slug.to_param([name, map[:start_year]], id)
  def slug_param(%{id: id} = map), do: Slug.to_param([map[:title]], id)
end
