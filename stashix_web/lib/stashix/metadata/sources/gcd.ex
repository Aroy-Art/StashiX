defmodule Stashix.Metadata.Sources.GCD do
  @moduledoc """
  Grand Comics Database (comics.org). Its REST API (https://www.comics.org/api/)
  takes basic auth with a comics.org account; anonymous access is heavily
  throttled (about 20/min, 200/hour, 2000/day). Credits and characters come as
  semicolon separated text and are parsed best-effort.

  The GCD notes that API field names are not yet stable.
  """
  @behaviour Stashix.Metadata.Source

  import Stashix.Metadata.Sources.Helpers
  alias Stashix.Metadata.{Candidate, HTTP}

  @impl true
  def key, do: "gcd"
  @impl true
  def name, do: "Grand Comics Database"
  @impl true
  def description, do: "Non-profit index of printed comics (comics.org). Login recommended."
  @impl true
  def homepage, do: "https://www.comics.org"
  @impl true
  def information_source, do: "Grand Comics Database"
  @impl true
  def default_rate_limit, do: {3, 60_000}

  @impl true
  def config_schema do
    [
      %{key: "username", label: "Email / username", type: :string, required: false},
      %{key: "password", label: "Password", type: :secret, required: false},
      %{
        key: "cookies",
        label: "Cookies",
        type: :cookies,
        required: false,
        help: "Optional. \"name=value; name2=value2\" or a Netscape cookies.txt export."
      }
    ]
  end

  @impl true
  def req_options(config) do
    base = [base_url: "https://www.comics.org/api"]

    case {config["username"], config["password"]} do
      {u, p} when is_binary(u) and u != "" and is_binary(p) and p != "" ->
        base ++ [auth: {:basic, "#{u}:#{p}"}]

      _ ->
        base
    end
  end

  defp enc(s), do: s |> to_string() |> URI.encode(&URI.char_unreserved?/1)

  @impl true
  def test_connection(ctx) do
    case HTTP.get(ctx, "/series/name/#{enc("batman")}/") do
      {:ok, %{"results" => _}} -> :ok
      {:ok, _} -> {:error, "Unexpected response"}
      {:error, reason} -> {:error, HTTP.error_message(reason)}
    end
  end

  @impl true
  def search_series(query, ctx) do
    path =
      if query[:year],
        do: "/series/name/#{enc(query[:name])}/year/#{query[:year]}/",
        else: "/series/name/#{enc(query[:name])}/"

    with {:ok, %{"results" => results}} <- HTTP.get(ctx, path) do
      {:ok, Enum.map(results, &series_candidate/1)}
    end
  end

  defp series_candidate(s) do
    id = id_from_url(s["api_url"])

    %Candidate{
      source_key: key(),
      kind: :series,
      id: id,
      series_id: id,
      series_name: s["name"],
      title: "#{s["name"]} (#{s["year_began"]})",
      year: int(s["year_began"]),
      issue_count: length(s["active_issues"] || []),
      url: "https://www.comics.org/series/#{id}/",
      raw: Map.drop(s, ["active_issues", "issue_descriptors"])
    }
  end

  @impl true
  def search_issues(%{series_id: series_id} = query, ctx) when is_binary(series_id) and series_id != "" do
    with {:ok, s} when is_map(s) <- HTTP.get(ctx, "/series/#{series_id}/") do
      wanted = normalize_descriptor(query[:number])

      candidates =
        Enum.zip(s["issue_descriptors"] || [], s["active_issues"] || [])
        |> Enum.filter(fn {descriptor, _} -> is_nil(wanted) or normalize_descriptor(descriptor) == wanted end)
        |> Enum.map(fn {descriptor, url} ->
          id = id_from_url(url)

          %Candidate{
            source_key: key(),
            kind: :issue,
            id: id,
            series_id: series_id,
            series_name: s["name"],
            number: descriptor,
            title: "#{s["name"]} ##{descriptor}",
            year: int(s["year_began"]),
            url: "https://www.comics.org/issue/#{id}/",
            raw: %{}
          }
        end)
        |> Enum.take(20)

      {:ok, candidates}
    end
  end

  def search_issues(query, ctx) do
    path =
      if query[:year],
        do: "/series/name/#{enc(query[:series_name])}/issue/#{enc(query[:number])}/year/#{query[:year]}/",
        else: "/series/name/#{enc(query[:series_name])}/issue/#{enc(query[:number])}/"

    with {:ok, %{"results" => results}} <- HTTP.get(ctx, path) do
      {:ok,
       results
       |> Enum.reject(&(&1["variant_of"] not in [nil, ""]))
       |> Enum.map(fn i ->
         id = id_from_url(i["api_url"])

         %Candidate{
           source_key: key(),
           kind: :issue,
           id: id,
           series_id: id_from_url(i["series"]),
           series_name: strip_year_suffix(i["series_name"]),
           number: i["descriptor"],
           title: "#{i["series_name"]} ##{i["descriptor"]}",
           year: gcd_date(i["publication_date"]) |> year_of() || year_in(i["publication_date"]),
           url: "https://www.comics.org/issue/#{id}/",
           raw: i
         }
       end)}
    end
  end

  # "2 [Newsstand]" -> "2", "001" -> "1"
  defp normalize_descriptor(nil), do: nil

  defp normalize_descriptor(d) do
    d
    |> to_string()
    |> String.replace(~r/\[.*?\]/, "")
    |> String.trim()
    |> Stashix.Metadata.Matcher.normalize_number()
  end

  @impl true
  def fetch_issue(id, ctx) do
    with {:ok, i} when is_map(i) <- HTTP.get(ctx, "/issue/#{id}/") do
      {:ok, issue_metadata(i, id)}
    end
  end

  @doc false
  def issue_metadata(i, id) do
    stories = i["story_set"] || []
    comic_stories = Enum.filter(stories, &(String.downcase(&1["type"] || "") in ["comic story", "story"]))
    key_date = gcd_date(i["key_date"])
    on_sale = gcd_date(i["on_sale_date"])
    title = first_present([i["title"] | Enum.map(comic_stories, & &1["title"])])

    %{}
    |> put(:series, strip_year_suffix(i["series_name"]))
    |> put(:issue_number, decimal(i["number"]))
    |> put(:volume, int(i["volume"]))
    |> put(:title, title)
    |> put(
      :stories,
      comic_stories |> Enum.map(& &1["title"]) |> Enum.reject(&blank?/1) |> Enum.map(&%{name: &1, external_id: nil})
    )
    |> put(:cover_date, key_date)
    |> put(:store_date, on_sale)
    |> put(:year, year_of(key_date) || year_in(i["publication_date"]))
    |> put(:publisher, strip_brackets(i["indicia_publisher"]))
    |> put(
      :page_count,
      i["page_count"] |> to_string() |> decimal() |> then(&(&1 && Decimal.to_integer(Decimal.round(&1))))
    )
    |> put(:summary, first_present(Enum.map(comic_stories, & &1["synopsis"])))
    |> put(:notes, i["notes"])
    |> put(:isbn, i["isbn"])
    |> put(:upc, i["barcode"])
    |> put(:genres, stories |> Enum.flat_map(&split_list(&1["genre"])) |> Enum.uniq())
    |> put(:credits, credits(stories, i["editing"]))
    |> put(
      :characters,
      stories |> Enum.flat_map(&split_list(&1["characters"])) |> Enum.uniq() |> Enum.map(&%{name: &1, external_id: nil})
    )
    |> put(:urls, [%{url: "https://www.comics.org/issue/#{id}/", is_primary: false}])
    |> put(:cover_url, i["cover"])
    |> put(:external_ids, [%{source: "Grand Comics Database", source_id: to_string(id), is_primary: false}])
    |> put(
      :series_external_ids,
      case id_from_url(i["series"]) do
        nil -> []
        sid -> [%{source: "Grand Comics Database", source_id: sid, is_primary: false}]
      end
    )
  end

  @story_roles [
    {"script", "Writer"},
    {"pencils", "Penciller"},
    {"inks", "Inker"},
    {"colors", "Colorist"},
    {"letters", "Letterer"},
    {"editing", "Editor"}
  ]

  defp credits(stories, issue_editing) do
    story_credits =
      Enum.flat_map(stories, fn story ->
        cover? = String.downcase(story["type"] || "") == "cover"

        Enum.flat_map(@story_roles, fn {field, role} ->
          role = if cover? and field in ["pencils", "inks"], do: "Cover", else: role
          Enum.map(split_list(story[field]), &{&1, role})
        end)
      end)

    (story_credits ++ Enum.map(split_list(issue_editing), &{&1, "Editor"}))
    |> Enum.reject(fn {name, _} -> String.downcase(name) in ["?", "various", "none", "typeset"] end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, roles} -> %{creator: name, creator_id: nil, roles: Enum.uniq(roles)} end)
  end

  # Splits "A; B [as C]; D (painted)" at top-level semicolons and strips notes.
  defp split_list(nil), do: []

  defp split_list(text) when is_binary(text) do
    text
    |> top_level_split()
    |> Enum.map(&strip_brackets/1)
    |> Enum.map(&String.trim_trailing(&1, "?"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&blank?/1)
  end

  defp top_level_split(text) do
    {parts, current, _depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", 0}, fn
        ";", {parts, cur, 0} -> {[cur | parts], "", 0}
        c, {parts, cur, d} when c in ["[", "("] -> {parts, cur <> c, d + 1}
        c, {parts, cur, d} when c in ["]", ")"] -> {parts, cur <> c, max(d - 1, 0)}
        c, {parts, cur, d} -> {parts, cur <> c, d}
      end)

    Enum.reverse([current | parts])
  end

  defp strip_brackets(nil), do: nil

  defp strip_brackets(s) do
    s
    |> String.replace(~r/\[[^\]]*\]/, "")
    |> String.replace(~r/\([^)]*\)/, "")
    |> String.trim()
  end

  defp first_present(list), do: Enum.find(list, &(not blank?(&1)))

  # GCD dates may be partial: "1940-04-00" or "1940-00-00".
  defp gcd_date(nil), do: nil

  defp gcd_date(s) when is_binary(s) do
    case Regex.run(~r/^(\d{4})-(\d{2})-(\d{2})/, s) do
      [_, y, m, d] ->
        m = max(String.to_integer(m), 1)
        d = max(String.to_integer(d), 1)

        case Date.new(String.to_integer(y), m, d) do
          {:ok, date} -> date
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp year_in(nil), do: nil

  defp year_in(s) do
    case Regex.run(~r/\b(1[89]\d{2}|2\d{3})\b/, s) do
      [_, y] -> String.to_integer(y)
      _ -> nil
    end
  end

  defp id_from_url(nil), do: nil

  defp id_from_url(url) do
    case Regex.run(~r{/(\d+)/?$}, url) do
      [_, id] -> id
      _ -> nil
    end
  end

  @impl true
  def fetch_series(id, ctx) do
    with {:ok, s} when is_map(s) <- HTTP.get(ctx, "/series/#{id}/") do
      {:ok,
       %{}
       |> put(:name, s["name"])
       |> put(:start_year, int(s["year_began"]))
       |> put(:end_year, int(s["year_ended"]))
       |> put(:issue_count, length(s["active_issues"] || []))
       |> put(:summary, s["notes"])
       |> put(:format, comic_format(s["publishing_format"]))
       |> Map.put(:ongoing, is_nil(s["year_ended"]))
       |> put(:external_ids, [%{source: "Grand Comics Database", source_id: to_string(id), is_primary: false}])}
    end
  end
end
