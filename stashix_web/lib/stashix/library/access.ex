# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.Access do
  @moduledoc """
  What a user may see: which libraries they can read and, per library, the
  highest age rating allowed.

  Admins see everything. Other users see books in libraries they have a
  `can_read` permission for, rated at or below that permission's
  `max_age_rating` (`:unknown` means no limit). Unrated books (`:unknown` or
  nil) stay visible under a limit unless the permission sets `hide_unrated`.

  Series are visible when they contain at least one visible, non-deleted book.

  Downloading a book's files needs `can_download` on top of `can_read`; admins
  can always download.
  """

  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, LibraryPermission, Series}

  # Ascending; :unknown is not a rating but "unrated".
  @rating_order [:everyone, :teen, :teen_plus, :mature, :adult, :explicit]

  defstruct all?: false, rules: [], downloads: []

  @type rule :: {library_id :: String.t(), ratings :: :all | [atom()], unrated? :: boolean()}
  @type t :: %__MODULE__{all?: boolean(), rules: [rule()], downloads: [String.t()]}

  @doc "Unrestricted access, for admins and internal callers."
  def all, do: %__MODULE__{all?: true}

  def for_user(%{role: :admin}), do: all()

  def for_user(%{id: user_id}) do
    permissions =
      from(p in LibraryPermission, where: p.user_id == ^user_id and p.can_read == true)
      |> Repo.all()

    %__MODULE__{
      rules: Enum.map(permissions, &rule/1),
      downloads: for(p <- permissions, p.can_download, do: p.library_id)
    }
  end

  def for_user(_), do: %__MODULE__{}

  defp rule(%LibraryPermission{library_id: lib, max_age_rating: max, hide_unrated: hide}) do
    case Enum.find_index(@rating_order, &(&1 == max)) do
      nil -> {lib, :all, true}
      idx -> {lib, Enum.take(@rating_order, idx + 1), not hide}
    end
  end

  @doc """
  The same access limited to `library_ids` (the libraries of one kind, for
  the browse switcher). Ratings limits stay as they were.
  """
  def narrow(%__MODULE__{all?: true}, library_ids),
    do: %__MODULE__{rules: Enum.map(library_ids, &{&1, :all, true}), downloads: library_ids}

  def narrow(%__MODULE__{rules: rules, downloads: downloads}, library_ids) do
    %__MODULE__{
      rules: Enum.filter(rules, &(elem(&1, 0) in library_ids)),
      downloads: Enum.filter(downloads, &(&1 in library_ids))
    }
  end

  @doc "Library ids the user can read, or `:all`."
  def library_ids(%__MODULE__{all?: true}), do: :all
  def library_ids(%__MODULE__{rules: rules}), do: Enum.map(rules, &elem(&1, 0))

  def can_read_library?(%__MODULE__{all?: true}, _library_id), do: true
  def can_read_library?(access, library_id), do: library_id in library_ids(access)

  @doc "Whether the user may download files from the library's books."
  def can_download?(%__MODULE__{all?: true}, _library_id), do: true
  def can_download?(%__MODULE__{downloads: downloads}, library_id), do: library_id in downloads

  @doc "Books the user may see (deleted ones included; callers filter those)."
  def books(%__MODULE__{all?: true}), do: from(b in Book)
  def books(access), do: from(b in Book, where: ^book_condition(access))

  @doc "Series the user may see."
  def series(%__MODULE__{all?: true}), do: from(s in Series)

  def series(access) do
    visible_series_ids =
      from(b in books(access), where: is_nil(b.deleted_at) and not is_nil(b.series_id), select: b.series_id)

    from(s in Series, where: s.id in subquery(visible_series_ids))
  end

  defp book_condition(%__MODULE__{rules: rules}) do
    Enum.reduce(rules, dynamic(false), fn rule, acc -> dynamic(^acc or ^rule_condition(rule)) end)
  end

  defp rule_condition({lib, :all, _unrated?}), do: dynamic([b], b.library_id == ^lib)

  defp rule_condition({lib, ratings, true}) do
    dynamic(
      [b],
      b.library_id == ^lib and (b.age_rating in ^[:unknown | ratings] or is_nil(b.age_rating))
    )
  end

  defp rule_condition({lib, ratings, false}) do
    dynamic([b], b.library_id == ^lib and b.age_rating in ^ratings)
  end
end
