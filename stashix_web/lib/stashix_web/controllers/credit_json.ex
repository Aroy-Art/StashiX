# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.CreditJSON do
  @moduledoc "Credit lists for the JSON API, shared by the book and search responses."

  alias Stashix.Metadata.Roles

  @doc "Preloads what `credits/1` reads on one book or a list of them."
  def preload(books), do: Stashix.Repo.preload(books, credits: :creator)

  @doc """
  A book's credits, one entry per creator and role. `role` is the detailed
  role ("Penciller"), `role_group` the heading it falls under ("Artist").
  """
  def credits(%{credits: credits}) when is_list(credits) do
    credits
    |> Enum.sort_by(fn c -> {Enum.find_index(Roles.headings(), &(&1 == Roles.group_of(c.role))), c.creator.name} end)
    |> Enum.map(fn c ->
      %{creator_id: c.creator.id, name: c.creator.name, role: c.role, role_group: Roles.group_of(c.role)}
    end)
  end

  def credits(_book), do: []
end
