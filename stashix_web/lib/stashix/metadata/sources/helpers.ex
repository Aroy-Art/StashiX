defmodule Stashix.Metadata.Sources.Helpers do
  @moduledoc "Small parsing helpers shared by source plugins."

  def blank?(v), do: v in [nil, "", []]

  def put(map, _key, v) when v in [nil, "", []], do: map
  def put(map, key, v), do: Map.put(map, key, v)

  def date(nil), do: nil

  def date(s) when is_binary(s) do
    case Date.from_iso8601(String.slice(s, 0, 10)) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  def int(nil), do: nil
  def int(i) when is_integer(i), do: i

  def int(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {i, _} -> i
      :error -> nil
    end
  end

  def int(_), do: nil

  def float(nil), do: nil
  def float(n) when is_number(n), do: n / 1

  def float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  def decimal(nil), do: nil
  def decimal(n) when is_integer(n), do: Decimal.new(n)
  def decimal(n) when is_float(n), do: Decimal.from_float(n)

  def decimal(s) when is_binary(s) do
    s = s |> String.trim() |> String.replace("½", ".5")

    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> nil
    end
  end

  def year_of(%Date{year: y}), do: y
  def year_of(_), do: nil

  @doc "Strips simple HTML (Comic Vine descriptions) to plain text."
  def strip_html(nil), do: nil

  def strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace(~r/<\/p>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
    |> case do
      "" -> nil
      s -> s
    end
  end

  @doc "\"Batman (2016)\" -> \"Batman\""
  def strip_year_suffix(nil), do: nil

  def strip_year_suffix(name),
    do: Regex.replace(~r/\s*\(\d{4}(?:\s*-\s*\d{0,4})?(?:\s+series)?\)\s*$/i, name, "")

  def names(list) when is_list(list), do: list |> Enum.map(& &1["name"]) |> Enum.reject(&blank?/1)
  def names(_), do: []

  def resources(list) when is_list(list) do
    list
    |> Enum.reject(&blank?(&1["name"]))
    |> Enum.map(&%{name: &1["name"], external_id: to_string(&1["id"])})
  end

  def resources(_), do: []

  @comic_formats ~w(Single\ Issue Trade\ Paperback Hardcover Graphic\ Novel Annual Digital\ Chapter Omnibus Compendium Treasury Facsimile\ Edition Preview)

  @doc "Maps a source's series-type string to a MetronInfo Format value, or nil."
  def comic_format(type) when type in [nil, ""], do: nil

  def comic_format(type) do
    t = String.downcase(type)

    cond do
      t in ["hard cover", "hardcover"] -> "Hardcover"
      String.contains?(t, "trade paperback") or t == "tpb" -> "Trade Paperback"
      String.contains?(t, "graphic novel") -> "Graphic Novel"
      String.contains?(t, "omnibus") -> "Omnibus"
      String.contains?(t, "annual") -> "Annual"
      String.contains?(t, "digital") -> "Digital Chapter"
      true -> Enum.find(@comic_formats, &(String.downcase(&1) == t)) || "Single Issue"
    end
  end

  @doc "Maps a rating string to the Book age_rating enum."
  def age_rating(nil), do: nil

  def age_rating(r) do
    case r |> String.downcase() |> String.trim() do
      "everyone" -> :everyone
      "all ages" -> :everyone
      "teen" -> :teen
      "teen plus" -> :teen_plus
      "mature" -> :mature
      "explicit" -> :explicit
      "adult" -> :adult
      _ -> nil
    end
  end
end
