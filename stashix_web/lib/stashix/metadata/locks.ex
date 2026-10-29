# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Locks do
  @moduledoc """
  Per-field locks on books and series (`locked_fields`).

  A locked field is never changed by a rescan or by metadata matching
  (Identify / auto-match); only the edit dialog can change it, after unlocking
  it there. File write-back still writes its value. This is finer than
  `metadata_locked`, which stops matching for the whole record.

  Keys are the field names of `Stashix.Metadata.Record` (`"title"`,
  `"credits"`, `"publisher"`, …), as strings.
  """

  @book_scalars ~w(title issue_number alternative_number volume year language age_rating summary notes
                   collection_title manga_volume cover_date store_date isbn upc community_rating
                   community_rating_count alternate_series alternate_count series_group
                   main_character_or_team scan_information review black_and_white manga)

  @book_lists ~w(genres tags stories characters teams locations reprints arcs universes credits urls prices
                 external_ids)

  @book_keys @book_scalars ++ ~w(publisher imprint) ++ @book_lists

  @series_keys ~w(name sort_name summary volume language format status start_year end_year ongoing issue_count
                  volume_count alternative_names publisher)

  def book_keys, do: @book_keys
  def book_scalars, do: @book_scalars
  def book_lists, do: @book_lists
  def series_keys, do: @series_keys

  @doc "Whether `key` (atom or string) is locked on the record."
  def locked?(%{locked_fields: fields}, key) when is_list(fields), do: to_string(key) in fields
  def locked?(_record, _key), do: false

  @doc "Drops the locked keys from a map of changes (atom or string keys)."
  def drop_locked(attrs, record) do
    Map.reject(attrs, fn {key, _} -> locked?(record, lock_key(key)) end)
  end

  # Columns whose lock key differs from the column name.
  defp lock_key(:imprint_id), do: :imprint
  defp lock_key("imprint_id"), do: :imprint
  defp lock_key(key), do: key

  @doc "Keeps only known keys, so a form can't store arbitrary strings."
  def clean(keys, allowed), do: keys |> Enum.map(&to_string/1) |> Enum.filter(&(&1 in allowed)) |> Enum.uniq()
end
