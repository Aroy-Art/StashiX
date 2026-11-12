# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

# Human-readable params for `~p"/series/#{series}"` and friends; see
# `Stashix.Slug`. API routes keep passing `.id` and stay plain UUIDs.

defimpl Phoenix.Param, for: Stashix.Library.Series do
  def to_param(s), do: Stashix.Slug.to_param([s.name, s.start_year], s.id)
end

defimpl Phoenix.Param, for: Stashix.Library.Book do
  alias Stashix.Library.Series

  # Issues read as "saga-2012-001"; standalone books, and books whose series
  # isn't preloaded, fall back to the title. Either form resolves, and the
  # page patches to the canonical one.
  def to_param(%{series: %Series{} = s, issue_number: %Decimal{} = n} = b),
    do: Stashix.Slug.to_param([s.name, s.start_year, issue(n)], b.id)

  def to_param(b), do: Stashix.Slug.to_param([b.title], b.id)

  # 1 → "001", 1.5 → "001.5" (slugged to "001-5")
  defp issue(n) do
    [int | frac] = n |> Stashix.Formatters.format_issue_number() |> String.split(".", parts: 2)
    Enum.join([pad(int) | frac], ".")
  end

  defp pad(int) do
    if int =~ ~r/\A\d+\z/, do: String.pad_leading(int, 3, "0"), else: int
  end
end

defimpl Phoenix.Param, for: Stashix.Library.Creator do
  def to_param(c), do: Stashix.Slug.to_param([c.name], c.id)
end

defimpl Phoenix.Param, for: Stashix.Library.Publisher do
  def to_param(p), do: Stashix.Slug.to_param([p.name], p.id)
end

defimpl Phoenix.Param, for: Stashix.Library.Library do
  def to_param(l), do: Stashix.Slug.to_param([l.name], l.id)
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
  def slug_param(%{id: _, issue_number: _, series: %Series{}} = book), do: Phoenix.Param.to_param(struct(Book, book))

  def slug_param(%{id: id, name: name} = map), do: Slug.to_param([name, map[:start_year]], id)
  def slug_param(%{id: id} = map), do: Slug.to_param([map[:title]], id)
end
