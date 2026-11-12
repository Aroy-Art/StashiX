# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Slug do
  @moduledoc """
  Human-readable URL params of the form `name-slug-<shortid>`.

  The short id is the first 12 hex digits of the record's UUID. Only that
  part is used for lookup, so renames never break a link; the slug is cosmetic.
  Full UUIDs are still accepted, which keeps old links and bookmarks working.

  A short id resolves through a range query on the primary key
  (`id BETWEEN prefix-000… AND prefix-fff…`), so it uses the existing index
  and needs no extra column.
  """

  import Ecto.Query

  alias Stashix.Repo

  @short_len 12
  @max_slug_len 60
  @uuid_re ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  @short_re ~r/(?:\A|-)([0-9a-f]{12})\z/i

  @doc """
  Builds the URL param for a record id, slugging `parts` (a string or a list;
  nil and empty entries are skipped).

      iex> Stashix.Slug.to_param(["Saga", 2012], "a7f3b2c9-1b04-4e1a-9c2f-8d6b5a0e1f23")
      "saga-2012-a7f3b2c91b04"
  """
  def to_param(parts, id) do
    case slugify(parts) do
      "" -> short(id)
      slug -> slug <> "-" <> short(id)
    end
  end

  @doc "The first #{@short_len} hex digits of a UUID."
  def short(uuid), do: uuid |> String.replace("-", "") |> String.downcase() |> binary_part(0, @short_len)

  @doc """
  Lowercase ASCII slug: accents stripped, every other run of non-alphanumerics
  collapsed to a single dash, capped at #{@max_slug_len} characters.

      iex> Stashix.Slug.slugify("Astérix & Obélix!")
      "asterix-obelix"
  """
  def slugify(parts) when is_list(parts) do
    parts
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map_join(" ", &to_string/1)
    |> slugify()
  end

  def slugify(nil), do: ""

  def slugify(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, @max_slug_len)
    |> String.trim_trailing("-")
  end

  @doc """
  Parses a URL param into `{:uuid, id}`, `{:range, lo, hi}` (a short id as an
  inclusive UUID range) or `:error`.
  """
  def parse(param) when is_binary(param) do
    cond do
      param =~ @uuid_re ->
        {:uuid, String.downcase(param)}

      match = Regex.run(@short_re, param, capture: :all_but_first) ->
        hex = match |> hd() |> String.downcase()
        {:range, pad_uuid(hex, "0"), pad_uuid(hex, "f")}

      true ->
        :error
    end
  end

  def parse(_), do: :error

  @doc """
  Resolves a URL param to the id of a `queryable` row.

  Raises `Ecto.NoResultsError` (a 404) when nothing matches, the param is
  malformed, or a short id is ambiguous. Access checks are left to the
  caller's usual getter.
  """
  def resolve!(queryable, param) do
    case resolve(queryable, param) do
      {:ok, id} -> id
      _ -> raise Ecto.NoResultsError, queryable: queryable
    end
  end

  @doc "Like `resolve!/2`, returning `{:ok, id}`, `:error` or `{:error, :ambiguous}`."
  def resolve(queryable, param) do
    case parse(param) do
      {:uuid, id} ->
        {:ok, id}

      {:range, lo, hi} ->
        from(r in queryable,
          where: r.id >= type(^lo, :binary_id) and r.id <= type(^hi, :binary_id),
          select: r.id,
          limit: 2
        )
        |> Repo.all()
        |> case do
          [id] -> {:ok, id}
          [] -> :error
          [_, _] -> {:error, :ambiguous}
        end

      :error ->
        :error
    end
  end

  defp pad_uuid(hex, fill) do
    <<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>> =
      hex <> String.duplicate(fill, 32 - @short_len)

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end
end
