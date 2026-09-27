defmodule Stashix.Metadata.Writer.XML do
  @moduledoc false
  # Tiny XML builder: nodes are {name, attrs, children | text}. Empty nodes are dropped.

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

  defp clean_attrs(attrs), do: Enum.reject(attrs, fn {_, v} -> v in [nil, ""] end)

  defp to_text(%Decimal{} = d), do: Decimal.to_string(d, :normal)
  defp to_text(%Date{} = d), do: Date.to_iso8601(d)
  defp to_text(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)
  defp to_text(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp to_text(v), do: to_string(v)

  defp render({name, attrs, children}, depth) when is_list(children) do
    pad = String.duplicate("  ", depth)

    [
      pad,
      "<",
      name,
      render_attrs(attrs),
      ">\n",
      Enum.map(children, &render(&1, depth + 1)),
      pad,
      "</",
      name,
      ">\n"
    ]
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
end
