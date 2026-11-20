# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Format.Opf do
  @moduledoc """
  OPF package metadata — Dublin Core plus Calibre's `calibre:*` meta — as a
  `Stashix.Metadata.Record`.

  Read from the `metadata.opf` Calibre keeps in each book folder and the
  `<book name>.opf` its "Save to disk" writes (`sidecar_path/1`). Values map as
  Calibre libraries map (`Stashix.Calibre.Mapper`), so a book reads the same
  from either.

  Besides the Record keys it gives `:sort_title` (`calibre:title_sort`) and
  `:rating` (`calibre:rating`, 0–10 → 0–5 stars). Both OPF 2 (`opf:role`,
  `opf:scheme`, `calibre:series`) and OPF 3 (`refines`, `belongs-to-collection`)
  forms are read.
  """

  import SweetXml, only: [sigil_x: 2, xpath: 2, xpath: 3]

  alias Stashix.Calibre.Mapper
  alias Stashix.Metadata.Format.XML

  # MARC relator codes → Stashix credit roles.
  @roles %{
    "aut" => "Writer",
    "trl" => "Translator",
    "ill" => "Illustrator",
    "art" => "Artist",
    "edt" => "Editor",
    "cov" => "Cover Artist",
    "clr" => "Colorist",
    "nrt" => "Narrator"
  }

  @doc """
  The OPF sidecar for a book file: `<book name>.opf` next to it, else the
  folder's `metadata.opf` when the folder holds one book (Calibre's layout).
  Nil when there is none.
  """
  def sidecar_path(file_path) do
    dir = Path.dirname(file_path)
    named = Path.join(dir, Stashix.Media.Formats.stem(file_path) <> ".opf")
    folder = Path.join(dir, "metadata.opf")

    cond do
      File.regular?(named) -> named
      File.regular?(folder) -> folder
      true -> nil
    end
  end

  @doc "Parses an OPF package (or a bare `<metadata>`) into a record."
  @spec parse(binary()) :: {:ok, map()} | {:error, term()}
  def parse(data) do
    with {:ok, doc} <- XML.parse_document(data) do
      metadata = xpath(doc, ~x"//*[local-name()='metadata'][1]"o) || doc
      {:ok, record(metadata)}
    end
  end

  defp record(md) do
    meta = named_meta(md)
    refines = refines(md)
    {series, index} = series(md, meta, refines)
    identifiers = identifiers(md)
    date = md |> text("date") |> date()

    %{}
    |> XML.put(:title, text(md, "title"))
    |> XML.put(:sort_title, XML.blank_to_nil(meta["calibre:title_sort"]))
    |> XML.put(:credits, credits(md, refines))
    |> XML.put(:summary, md |> text("description") |> Mapper.html_to_text())
    |> XML.put(:publisher, text(md, "publisher"))
    |> XML.put(:language, md |> text("language") |> Mapper.language())
    |> XML.put(:cover_date, date)
    |> XML.put(:year, date && date.year)
    |> XML.put(:tags, md |> texts("subject") |> Enum.uniq())
    |> XML.put(:series, series)
    |> XML.put(:issue_number, series && index)
    |> XML.put(:rating, rating(meta["calibre:rating"]))
    |> XML.put(:isbn, identifiers["isbn"])
    |> XML.put(:external_ids, external_ids(identifiers))
  end

  # `<meta name="…" content="…"/>` (OPF 2) and `<meta property="…">…</meta>`
  # without `refines` (OPF 3), by name.
  defp named_meta(md) do
    opf2 =
      md
      |> xpath(~x"./*[local-name()='meta'][@name]"l, name: ~x"./@name"s, content: ~x"./@content"s)
      |> Map.new(&{&1.name, &1.content})

    opf3 =
      md
      |> xpath(~x"./*[local-name()='meta'][@property and not(@refines)]"l, name: ~x"./@property"s, text: ~x"./text()"s)
      |> Map.new(&{&1.name, String.trim(&1.text)})

    Map.merge(opf3, opf2)
  end

  # OPF 3 `<meta refines="#id" property="…">`, as `%{id => %{property => value}}`.
  defp refines(md) do
    md
    |> xpath(~x"./*[local-name()='meta'][@refines]"l,
      id: ~x"./@refines"s,
      property: ~x"./@property"s,
      text: ~x"./text()"s
    )
    |> Enum.reduce(%{}, fn m, acc ->
      id = String.trim_leading(m.id, "#")
      Map.update(acc, id, %{m.property => String.trim(m.text)}, &Map.put_new(&1, m.property, String.trim(m.text)))
    end)
  end

  defp credits(md, refines) do
    md
    |> xpath(~x"./*[local-name()='creator' or local-name()='contributor']"l,
      name: ~x"./text()"s,
      id: ~x"./@id"s,
      role: ~x"./@*[local-name()='role']"s
    )
    |> Enum.flat_map(fn c ->
      role = XML.blank_to_nil(c.role) || get_in(refines, [c.id, "role"]) || "aut"
      name = String.trim(c.name)

      case @roles[String.downcase(role)] do
        nil -> []
        _ when name == "" -> []
        stashix_role -> [%{creator: name, roles: [stashix_role]}]
      end
    end)
    |> Enum.group_by(& &1.creator)
    |> Enum.map(fn {name, rows} -> %{creator: name, roles: rows |> Enum.flat_map(& &1.roles) |> Enum.uniq()} end)
    |> Enum.sort_by(& &1.creator)
  end

  defp series(md, meta, refines) do
    case XML.blank_to_nil(meta["calibre:series"]) do
      nil ->
        # OPF 3: the first `belongs-to-collection`, with its `group-position`.
        case xpath(md, ~x"./*[local-name()='meta'][@property='belongs-to-collection'][1]"o) do
          nil ->
            {nil, nil}

          node ->
            id = xpath(node, ~x"./@id"s)
            {node |> xpath(~x"./text()"s) |> XML.blank_to_nil(), index(get_in(refines, [id, "group-position"]))}
        end

      name ->
        {name, index(meta["calibre:series_index"])}
    end
  end

  defp index(value) do
    case value && Decimal.parse(String.trim(value)) do
      {d, ""} -> Decimal.normalize(d)
      _ -> nil
    end
  end

  # `%{type => value}` from `opf:scheme` (OPF 2) or a `type:value` text (OPF 3,
  # `urn:isbn:…`), type lower-case.
  defp identifiers(md) do
    md
    |> xpath(~x"./*[local-name()='identifier']"l, value: ~x"./text()"s, scheme: ~x"./@*[local-name()='scheme']"s)
    |> Enum.flat_map(fn %{value: value, scheme: scheme} ->
      value = String.trim(value)

      cond do
        value == "" -> []
        scheme != "" -> [{String.downcase(scheme), value}]
        match = Regex.run(~r/^urn:isbn:(.+)$/i, value) -> [{"isbn", List.last(match)}]
        match = Regex.run(~r/^([a-z_-]+):(.+)$/i, value) -> [{String.downcase(Enum.at(match, 1)), List.last(match)}]
        true -> []
      end
    end)
    |> Enum.reverse()
    |> Map.new()
  end

  defp external_ids(identifiers) do
    identifiers
    |> Enum.sort_by(fn {type, _} -> {type != "amazon", type} end)
    |> Enum.flat_map(fn {type, value} ->
      case Mapper.source(type) do
        nil -> []
        source -> [%{source: source, source_id: value, is_primary: false}]
      end
    end)
    |> Enum.uniq_by(& &1.source)
  end

  # "2017-09-12T04:00:00+00:00", "2017-09-12", "2017-09" or "2017"; Calibre's
  # year 101 means unknown.
  defp date(nil), do: nil

  defp date(value) do
    case Regex.run(~r/^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?/, value) do
      [_, y | rest] ->
        [m, d] = rest |> Enum.concat(["01", "01"]) |> Enum.take(2) |> Enum.map(&if(&1 == "", do: "01", else: &1))

        case Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)) do
          {:ok, %Date{year: year} = date} when year > 101 -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp rating(value) do
    case value && Float.parse(value) do
      {n, _} when n > 0 -> min(n, 10.0) / 2
      _ -> nil
    end
  end

  defp text(md, name), do: md |> texts(name) |> List.first()

  defp texts(md, name) do
    md
    |> xpath(~x"./*[local-name()='#{name}']/text()"ls)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
