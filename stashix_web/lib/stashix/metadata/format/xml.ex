# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.Format.XML do
  @moduledoc false
  # Shared XML plumbing for the metadata formats.
  #
  # Building: nodes are {name, attrs, children | text}; empty nodes and nil
  # attributes are dropped, so builders can pass every field unconditionally.
  #
  # Parsing: metadata in library files is untrusted, so DTDs/entities are never
  # resolved, and malformed input yields `{:error, _}` instead of raising.

  import SweetXml, only: [parse: 2]

  def document(root) do
    IO.iodata_to_binary([~s(<?xml version="1.0" encoding="UTF-8"?>\n), render(root, 0)])
  end

  def el(name, attrs \\ [], content)

  def el(_name, _attrs, content) when content in [nil, "", []], do: nil

  def el(name, attrs, content) when is_list(content) do
    case Enum.reject(content, &is_nil/1) do
      [] -> nil
      children -> {name, clean_attrs(attrs), children}
    end
  end

  def el(name, attrs, content), do: {name, clean_attrs(attrs), to_text(content)}

  @doc "An element with attributes only (`<Page Image=\"0\"/>`); dropped when it has none."
  def empty_el(name, attrs) do
    case clean_attrs(attrs) do
      [] -> nil
      attrs -> {name, attrs, :empty}
    end
  end

  defp clean_attrs(attrs), do: Enum.reject(attrs, fn {_, v} -> v in [nil, ""] end)

  defp to_text(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp to_text(%Date{} = d), do: Date.to_iso8601(d)
  defp to_text(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)
  defp to_text(%DateTime{} = d), do: DateTime.to_iso8601(d)
  defp to_text(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp to_text(v), do: to_string(v)

  defp render({name, attrs, :empty}, depth) do
    [String.duplicate("  ", depth), "<", name, render_attrs(attrs), " />\n"]
  end

  defp render({name, attrs, children}, depth) when is_list(children) do
    pad = String.duplicate("  ", depth)
    [pad, "<", name, render_attrs(attrs), ">\n", Enum.map(children, &render(&1, depth + 1)), pad, "</", name, ">\n"]
  end

  defp render({name, attrs, text}, depth) do
    [String.duplicate("  ", depth), "<", name, render_attrs(attrs), ">", escape(text), "</", name, ">\n"]
  end

  defp render_attrs(attrs), do: Enum.map(attrs, fn {k, v} -> [" ", to_string(k), "=\"", escape(to_text(v)), "\""] end)

  def escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    # Strip characters not allowed in XML 1.0
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
  end

  @doc "Parses untrusted XML. `{:ok, doc}` or `{:error, reason}`, never raises."
  def parse_document(data) when is_binary(data) do
    {:ok, data |> sanitize() |> parse(dtd: :none, quiet: true)}
  rescue
    e -> {:error, e}
  catch
    :exit, reason -> {:error, reason}
  end

  # xmerl is fatal on duplicate namespace declarations; deduplicate xmlns:* attrs.
  defp sanitize(data) do
    Regex.replace(
      ~r/(<[A-Za-z][^>]*?)((\s+xmlns:[A-Za-z0-9_]+=("[^"]*"|'[^']*'))+)/,
      data,
      fn _, tag_open, ns_block, _, _ ->
        deduped =
          Regex.scan(~r/\s+xmlns:[A-Za-z0-9_]+=(?:"[^"]*"|'[^']*')/, ns_block)
          |> Enum.map(&hd/1)
          |> Enum.uniq_by(fn attr -> Regex.run(~r/xmlns:[A-Za-z0-9_]+/, attr) end)
          |> Enum.join("")

        tag_open <> deduped
      end
    )
  end

  ## Value helpers shared by the format readers

  def blank_to_nil(nil), do: nil

  def blank_to_nil(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  def parse_int(s) do
    with s when is_binary(s) <- blank_to_nil(s),
         {n, _} <- Integer.parse(s) do
      n
    else
      _ -> nil
    end
  end

  def parse_decimal(s) do
    with s when is_binary(s) <- blank_to_nil(s),
         {d, _} <- Decimal.parse(s) do
      d
    else
      _ -> nil
    end
  end

  def parse_float(s) do
    with s when is_binary(s) <- blank_to_nil(s),
         {f, _} <- Float.parse(s) do
      f
    else
      _ -> nil
    end
  end

  def parse_date(s) do
    with s when is_binary(s) <- blank_to_nil(s),
         {:ok, d} <- Date.from_iso8601(s) do
      d
    else
      _ -> nil
    end
  end

  def parse_bool(s), do: s |> blank_to_nil() |> then(&(&1 in ["true", "1"]))

  @doc "Puts `value` unless it is nil, blank or an empty list."
  def put(map, _key, nil), do: map
  def put(map, _key, ""), do: map
  def put(map, _key, []), do: map
  def put(map, key, value), do: Map.put(map, key, value)
end
