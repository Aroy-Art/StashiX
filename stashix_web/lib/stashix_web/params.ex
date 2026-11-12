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
