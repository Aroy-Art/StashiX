# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.Locator do
  @moduledoc """
  Where in a book something is: the reading position
  (`Stashix.Library.ReadingProgress`) and annotations
  (`Stashix.Library.Annotation`) share this shape. Each reader has a type:

      %{"type" => "image", "page" => 12}
      %{"type" => "image", "page" => 12, "rect" => [0.1, 0.2, 0.3, 0.15]}
      %{"type" => "pdf", "page" => 12}
      %{"type" => "pdf", "page" => 12, "rects" => [[0.1, 0.2, 0.5, 0.02], ...]}
      %{"type" => "epub", "cfi" => "epubcfi(/6/8!/4/2/1:0)", "href" => "OEBPS/ch3.xhtml"}
      %{"type" => "mobi" | "fb2", "cfi" => "epubcfi(...)"}

  Rects are `[x, y, width, height]` as shares (0..1) of the page, so they
  hold at any size, fit or zoom. A CFI may be a range (a highlight).
  (Kindle and FictionBook books are laid out by foliate-js like EPUB, so
  their spots are CFIs over foliate-js's sections too.)
  """

  @types ~w(image pdf epub mobi fb2)
  @max_string 1024
  @max_rects 200

  @doc "The locator from client params, keeping only what fits the shapes above; nil if none."
  @spec from_params(term()) :: map() | nil
  def from_params(%{"type" => type} = locator) when type in @types do
    %{"type" => type}
    |> put_if(locator, "page", &(is_integer(&1) and &1 >= 0))
    |> put_if(locator, "cfi", &(is_binary(&1) and String.starts_with?(&1, "epubcfi(") and byte_size(&1) <= @max_string))
    |> put_if(locator, "href", &(is_binary(&1) and byte_size(&1) <= @max_string))
    |> put_rect(locator["rect"])
    |> put_rects(locator["rects"])
  end

  def from_params(_), do: nil

  defp put_if(acc, locator, key, valid?) do
    if valid?.(locator[key]), do: Map.put(acc, key, locator[key]), else: acc
  end

  defp put_rect(acc, rect) do
    case rect(rect) do
      nil -> acc
      rect -> Map.put(acc, "rect", rect)
    end
  end

  defp put_rects(acc, rects) when is_list(rects) and length(rects) in 1..@max_rects do
    case Enum.map(rects, &rect/1) do
      list -> if nil in list, do: acc, else: Map.put(acc, "rects", list)
    end
  end

  defp put_rects(acc, _rects), do: acc

  @doc "A `[x, y, w, h]` rect clamped to the page, or nil when it isn't one."
  def rect([x, y, w, h]) when is_number(x) and is_number(y) and is_number(w) and is_number(h) do
    x = clamp(x)
    y = clamp(y)
    w = min(clamp(w), 1.0 - x)
    h = min(clamp(h), 1.0 - y)
    if w > 0 and h > 0, do: Enum.map([x, y, w, h], &Float.round(&1, 5))
  end

  def rect(_), do: nil

  defp clamp(n), do: n |> max(0) |> min(1) |> Kernel.*(1.0)
end
