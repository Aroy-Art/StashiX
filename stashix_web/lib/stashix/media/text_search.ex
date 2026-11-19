# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.TextSearch do
  @moduledoc """
  Full-text search inside a text book, done here so the reader doesn't have
  to download the whole book to search it.

  - EPUB: each spine document, in spine order (the order and numbering of
    foliate-js's sections). A hit is the section and which match in it it
    is; the reader opens only that section to find its exact spot.
  - PDF: each page's text from `pdftotext`. A hit is the page.

  Matching follows foliate-js's default search, so a hit's number within its
  section is the same one the reader finds: the text is the section body's
  text nodes run together (no scripts or styles), whitespace runs count as
  one space, format characters (soft hyphens, joiners) are skipped, and case
  and accents don't matter.

  A book's text is extracted once and kept in `Stashix.Media.PageCache`.
  Other formats return `{:error, :unsupported}`: the reader searches those
  itself.
  """

  alias Stashix.Media.{Epub, PageCache}

  @max_hits 500
  # Marks where blocks meet while extracting (a private-use character).
  @block "\u{E000}"
  @blocks ~w(p div h1 h2 h3 h4 h5 h6 li dt dd blockquote pre section article aside header footer
             nav figure figcaption table tr td th caption br hr ul ol dl body)
  # Characters of context each side of a hit.
  @context 40

  @type hit :: %{
          section: non_neg_integer(),
          n: non_neg_integer(),
          href: String.t() | nil,
          before: String.t(),
          match: String.t(),
          after: String.t()
        }

  @doc "Whether `format` is searched here."
  @spec supported?(atom()) :: boolean()
  def supported?(format), do: format in [:epub, :pdf]

  @doc """
  Hits for `query` in reading order, at most #{@max_hits}. `section` is the
  spine index (EPUB) or 0-based page (PDF); `n` counts from 0 within it.
  """
  @spec search(atom(), Path.t(), String.t()) :: {:ok, [hit()]} | {:error, term()}
  def search(format, path, query) do
    with true <- supported?(format) || {:error, :unsupported},
         needle when needle != "" <- query |> display() |> fold(),
         {:ok, sections} <- sections(format, path) do
      {:ok, find(sections, needle)}
    else
      "" -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp find(sections, needle) do
    sections
    |> Stream.flat_map(fn {index, href, text, folded, breaks} ->
      text
      |> matches(folded, needle, breaks)
      |> Enum.with_index(fn hit, n -> Map.merge(hit, %{section: index, n: n, href: href}) end)
    end)
    |> Enum.take(@max_hits)
  end

  # Every start of `needle` in `folded`, overlaps included, as foliate-js
  # finds them. `folded` has a grapheme for each of `text`'s, so a hit's
  # grapheme position there is its position in `text`.
  #
  # Hits come in order, so both strings are walked once: `pos`/`at` is the
  # last hit's byte offset in `folded` and grapheme offset, `rest` is `text`
  # from grapheme `rest_at` on.
  #
  # Where blocks meet with no whitespace between them (`breaks`, grapheme
  # offsets), the excerpt gets a space, so paragraphs don't run together.
  defp matches(text, folded, needle, breaks) do
    len = String.length(needle)

    folded
    |> starts(needle, 0, [])
    |> Enum.reverse()
    |> Enum.map_reduce({0, 0, text, 0}, fn pos, {last_pos, last_at, rest, rest_at} ->
      at = last_at + String.length(binary_part(folded, last_pos, pos - last_pos))
      from = max(at - @context, 0)
      {_, rest} = String.split_at(rest, from - rest_at)
      {before, tail} = String.split_at(rest, at - from)
      {match, tail} = String.split_at(tail, len)
      after_ = String.slice(tail, 0, @context)

      hit = %{
        before: spaced(before, from, breaks),
        match: spaced(match, at, breaks),
        after: spaced(after_, at + len, breaks)
      }

      {hit, {pos, at, rest, from}}
    end)
    |> elem(0)
  end

  # `str` starts at grapheme `from`; a space goes in at each break inside it
  # or at its end (not at its start: the previous part ends with it).
  defp spaced(str, from, breaks) do
    to = from + String.length(str)

    breaks
    |> Enum.filter(&(&1 > from and &1 <= to))
    |> Enum.reverse()
    |> Enum.reduce(str, fn at, str ->
      {a, b} = String.split_at(str, at - from)
      a <> " " <> b
    end)
  end

  # The needle starts with a UTF-8 lead byte, so stepping on by one byte
  # still only ever matches at a character.
  defp starts(folded, needle, from, acc) do
    case :binary.match(folded, needle, scope: {from, byte_size(folded) - from}) do
      {pos, _} -> starts(folded, needle, pos + 1, [pos | acc])
      :nomatch -> acc
    end
  end

  ## Text

  # `{index, href, text, folded, breaks}` per section: `text` as matched,
  # `breaks` where blocks meet in it.
  defp sections(format, path) do
    PageCache.fetch(path, :search_text, fn ->
      with {:ok, texts} <- texts(format, path) do
        {:ok,
         for {{href, raw}, index} <- Enum.with_index(texts),
             {text, breaks} = split_breaks(raw),
             text != "" do
           {index, href, text, fold(text), breaks}
         end}
      end
    end)
  end

  # Takes out the block marks, noting where they were. A mark next to
  # whitespace adds nothing: the space is there already.
  defp split_breaks(raw) do
    parts =
      raw
      |> display()
      |> String.replace(~r/^[ #{@block}]+|[ #{@block}]+$/u, "")
      |> String.replace(~r/ ?#{@block}[ #{@block}]*/u, fn run -> if run =~ " ", do: " ", else: @block end)
      |> String.split(@block)

    {breaks, _} =
      parts
      |> Enum.drop(-1)
      |> Enum.map_reduce(0, fn part, at -> {at + String.length(part), at + String.length(part)} end)

    {Enum.join(parts), breaks}
  end

  defp texts(:epub, path) do
    with {:ok, %{spine: spine}} <- Epub.package(path) do
      {:ok, Enum.map(spine, fn %{item: item} -> {item.href, document_text(path, item)} end)}
    end
  end

  # pdftotext ends every page with a form feed.
  defp texts(:pdf, path) do
    case System.cmd("pdftotext", ["-q", "-enc", "UTF-8", "--", path, "-"]) do
      {out, 0} -> {:ok, out |> String.split("\f") |> Enum.drop(-1) |> Enum.map(&{nil, &1})}
      {_, status} -> {:error, {"pdftotext", status}}
    end
  rescue
    ErlangError -> {:error, :pdftotext_not_found}
  end

  # Pictures and other non-documents in the spine have no text.
  defp document_text(path, %{href: href, media_type: type}) do
    with true <- type =~ ~r/html|xml/,
         {:ok, data} <- Epub.read(path, href),
         {:ok, doc} <- Floki.parse_document(data) do
      doc |> Floki.find("body") |> block_text()
    else
      _ -> ""
    end
  end

  # The text nodes run together, as foliate-js reads them, with a mark
  # where a block starts or ends.
  defp block_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &block_text/1)
  defp block_text(text) when is_binary(text), do: text
  defp block_text({tag, _, _}) when tag in ["script", "style"], do: ""
  defp block_text({tag, _, children}) when tag in @blocks, do: @block <> block_text(children) <> @block
  defp block_text({tag, _, children}) when is_binary(tag), do: block_text(children)
  defp block_text(_comment_or_other), do: ""

  # Whitespace runs as one space, no format characters.
  defp display(text) do
    text
    |> String.replace(~r/\p{Cf}+/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # Case and accents dropped, a grapheme for a grapheme.
  defp fold(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}+/u, "")
  end
end
