defmodule Stashix.Metadata.Sources.Metron do
  @moduledoc """
  metron.cloud — community comic database whose data model MetronInfo is built on.
  API docs: https://metron.cloud/docs/  (basic auth, ~20 req/min burst).
  """
  @behaviour Stashix.Metadata.Source

  import Stashix.Metadata.Sources.Helpers
  alias Stashix.Metadata.{Candidate, HTTP}

  @impl true
  def key, do: "metron"
  @impl true
  def name, do: "Metron"
  @impl true
  def description, do: "Community comic database (metron.cloud). Requires a free account."
  @impl true
  def homepage, do: "https://metron.cloud"
  @impl true
  def information_source, do: "Metron"
  @impl true
  def default_rate_limit, do: {20, 60_000}

  @impl true
  def config_schema do
    [
      %{key: "username", label: "Username", type: :string, required: true},
      %{key: "password", label: "Password", type: :secret, required: true},
      %{
        key: "base_url",
        label: "API URL",
        type: :string,
        default: "https://metron.cloud/api",
        help: "Only change for a self-hosted Metron instance"
      }
    ]
  end

  @impl true
  def req_options(config) do
    base = [base_url: blank_default(config["base_url"], "https://metron.cloud/api")]

    case {config["username"], config["password"]} do
      {u, p} when is_binary(u) and u != "" and is_binary(p) -> base ++ [auth: {:basic, "#{u}:#{p}"}]
      _ -> base
    end
  end

  defp blank_default(v, default), do: if(blank?(v), do: default, else: String.trim_trailing(v, "/"))

  @impl true
  def test_connection(ctx) do
    case HTTP.get(ctx, "/publisher/", params: [name: "marvel"]) do
      {:ok, %{"count" => _}} -> :ok
      {:ok, _} -> {:error, "Unexpected response"}
      {:error, reason} -> {:error, HTTP.error_message(reason)}
    end
  end

  @impl true
  def search_series(query, ctx) do
    params = [name: query[:name]] |> maybe_param(:year_began, query[:year])

    with {:ok, %{"results" => results}} <- HTTP.get(ctx, "/series/", params: params, cache: :short),
         results = retry_without_year(results, query, ctx) do
      {:ok, Enum.map(results, &series_candidate/1)}
    end
  end

  # Metron's year_began filter is exact; fall back to name only when it finds nothing.
  defp retry_without_year([], %{year: y} = query, ctx) when not is_nil(y) do
    case HTTP.get(ctx, "/series/", params: [name: query[:name]], cache: :short) do
      {:ok, %{"results" => r}} -> r
      _ -> []
    end
  end

  defp retry_without_year(results, _, _), do: results

  defp series_candidate(s) do
    display = s["series"] || s["name"]

    %Candidate{
      source_key: key(),
      kind: :series,
      id: to_string(s["id"]),
      series_id: to_string(s["id"]),
      series_name: strip_year_suffix(display),
      title: display,
      year: s["year_began"],
      issue_count: s["issue_count"],
      publisher: get_in(s, ["publisher", "name"]),
      url: "https://metron.cloud/series/#{s["id"]}/",
      raw: s
    }
  end

  @impl true
  def search_issues(query, ctx) do
    params =
      []
      |> maybe_param(:series_id, query[:series_id])
      |> maybe_param(:series_name, if(blank?(query[:series_id]), do: query[:series_name]))
      |> maybe_param(:number, query[:number])
      |> maybe_param(:cover_year, if(blank?(query[:series_id]), do: query[:year]))

    with {:ok, %{"results" => results}} <- HTTP.get(ctx, "/issue/", params: params, cache: :short) do
      {:ok, Enum.map(results, &issue_candidate/1)}
    end
  end

  defp issue_candidate(i) do
    cover_date = date(i["cover_date"])

    %Candidate{
      source_key: key(),
      kind: :issue,
      id: to_string(i["id"]),
      series_id: get_in(i, ["series", "id"]) && to_string(get_in(i, ["series", "id"])),
      series_name: get_in(i, ["series", "name"]),
      number: i["number"],
      title: i["issue"],
      year: year_of(cover_date),
      cover_url: i["image"],
      url: "https://metron.cloud/issue/#{i["id"]}/",
      raw: i
    }
  end

  defp maybe_param(params, _k, v) when v in [nil, ""], do: params
  defp maybe_param(params, k, v), do: params ++ [{k, v}]

  @impl true
  def fetch_issue(id, ctx) do
    with {:ok, i} when is_map(i) <- HTTP.get(ctx, "/issue/#{id}/", cache: :long) do
      {:ok, issue_metadata(i)}
    end
  end

  @doc false
  def issue_metadata(i) do
    series = i["series"] || %{}
    cover_date = date(i["cover_date"])
    store_date = date(i["store_date"])
    stories = i["name"] || []

    %{}
    |> put(:series, series["name"])
    |> put(:series_sort_name, series["sort_name"])
    |> put(:volume, series["volume"])
    |> put(:series_format, comic_format(get_in(series, ["series_type", "name"])))
    |> put(:series_start_year, series["year_began"])
    |> put(:language, series["language"])
    |> put(:issue_number, decimal(i["number"]))
    |> put(:alternative_number, i["alt_number"])
    |> put(:collection_title, i["title"])
    |> put(:title, List.first(stories))
    |> put(:stories, Enum.map(stories, &%{name: &1, external_id: nil}))
    |> put(:cover_date, cover_date)
    |> put(:store_date, store_date)
    |> put(:year, year_of(cover_date) || year_of(store_date))
    |> put(:publisher, get_in(i, ["publisher", "name"]))
    |> put(:imprint, get_in(i, ["imprint", "name"]))
    |> put(:page_count, int(i["page"]))
    |> put(:summary, i["desc"])
    |> put(:age_rating, age_rating(get_in(i, ["rating", "name"])))
    |> put(:isbn, i["isbn"])
    |> put(:upc, i["upc"])
    |> put(:genres, names(series["genres"]))
    |> put(:arcs, Enum.map(resources(i["arcs"]), &Map.put(&1, :arc_number, nil)))
    |> put(:credits, credits(i["credits"]))
    |> put(:characters, resources(i["characters"]))
    |> put(:teams, resources(i["teams"]))
    |> put(:universes, Enum.map(resources(i["universes"]), &Map.put(&1, :designation, nil)))
    |> put(:reprints, reprints(i["reprints"]))
    |> put(:urls, if(i["resource_url"], do: [%{url: i["resource_url"], is_primary: true}], else: []))
    |> put(:prices, prices(i["price"], i["price_currency"]))
    |> put(:cover_url, i["image"])
    |> put(:external_ids, external_ids(i["id"], i["cv_id"], i["gcd_id"]))
    |> put(:series_external_ids, external_ids(series["id"], nil, nil))
  end

  defp credits(list) when is_list(list) do
    list
    |> Enum.reject(&blank?(&1["creator"]))
    |> Enum.map(fn c ->
      %{creator: c["creator"], creator_id: to_string(c["id"]), roles: names(c["role"])}
    end)
  end

  defp credits(_), do: []

  defp reprints(list) when is_list(list) do
    list
    |> Enum.reject(&blank?(&1["issue"]))
    |> Enum.map(&%{name: &1["issue"], external_id: to_string(&1["id"])})
  end

  defp reprints(_), do: []

  @currency_country %{"USD" => "US", "CAD" => "CA", "GBP" => "GB", "AUD" => "AU", "JPY" => "JP"}

  defp prices(nil, _), do: []

  defp prices(amount, currency) do
    case {decimal(to_string(amount)), Map.get(@currency_country, currency || "USD")} do
      {%Decimal{} = d, country} when is_binary(country) -> [%{amount: d, country: country}]
      _ -> []
    end
  end

  defp external_ids(nil, _, _), do: []

  defp external_ids(id, cv_id, gcd_id) do
    [%{source: "Metron", source_id: to_string(id), is_primary: true}]
    |> then(&if cv_id, do: &1 ++ [%{source: "Comic Vine", source_id: to_string(cv_id), is_primary: false}], else: &1)
    |> then(
      &if gcd_id,
        do: &1 ++ [%{source: "Grand Comics Database", source_id: to_string(gcd_id), is_primary: false}],
        else: &1
    )
  end

  @impl true
  def fetch_series(id, ctx) do
    with {:ok, s} when is_map(s) <- HTTP.get(ctx, "/series/#{id}/", cache: :long) do
      {:ok,
       %{}
       |> put(:name, s["name"])
       |> put(:sort_name, s["sort_name"])
       |> put(:volume, s["volume"])
       |> put(:format, comic_format(get_in(s, ["series_type", "name"])))
       |> put(:start_year, s["year_began"])
       |> put(:end_year, s["year_end"])
       |> put(:issue_count, s["issue_count"])
       |> put(:summary, s["desc"])
       |> put(:publisher, get_in(s, ["publisher", "name"]))
       |> put(:language, s["language"])
       |> Map.put(:ongoing, is_nil(s["year_end"]) and get_in(s, ["status"]) in [nil, "Ongoing"])
       |> put(:external_ids, external_ids(s["id"], s["cv_id"], s["gcd_id"]))}
    end
  end
end
