defmodule Stashix.Metadata.Sources.ComicVine do
  @moduledoc """
  Metadata source backed by the Comic Vine API (comicvine.gamespot.com/api/).

  ## Authentication
  A free API key is required. Obtain one at https://comicvine.gamespot.com/api/.

  ## Rate limits
  The API enforces 200 requests per resource per hour. Rapid bursts are flagged
  server-side and result in a status 107 response (undocumented but observed in
  practice). The default rate limit is kept deliberately conservative.

  ## Response status codes
  | Code | Meaning              |
  |------|----------------------|
  | 1    | OK                   |
  | 100  | Invalid API key      |
  | 101  | Object not found     |
  | 102  | URL format error     |
  | 104  | Filter error         |
  | 105  | Subscriber-only      |
  | 107  | Rate limited (undoc) |

  ## Object ID prefixes
  Comic Vine single-object endpoints require a resource-type prefix on the ID:
  - Issues use `4000-<id>`   → `/issue/4000-123/`
  - Volumes use `4050-<id>`  → `/volume/4050-456/`

  ## Pagination
  List endpoints default to 100 results per page (maximum 100). Responses
  include `number_of_total_results` for offset-based navigation.
  """
  @behaviour Stashix.Metadata.Source

  import Stashix.Metadata.Sources.Helpers
  alias Stashix.Metadata.{Candidate, HTTP}

  @issue_list_fields ~w(id name issue_number cover_date store_date volume image site_detail_url)
  @issue_fields ~w(id name issue_number cover_date store_date description volume image site_detail_url
                   person_credits character_credits team_credits location_credits story_arc_credits
                   concept_credits aliases)
  @volume_fields ~w(id name start_year publisher count_of_issues image site_detail_url description)

  # Comic Vine stores collected-edition titles as a format abbreviation rather than
  # a real title; these should be ignored so the volume/series name is used instead.
  @format_labels ~w(tpb hc gn omnibus sc hb)
  @format_label_patterns [
    ~r/^(trade\s+paperback|hard\s*cover|graphic\s+novel|omnibus|special\s+edition)$/i,
    ~r/^(vol\.?|volume|book)\s*\d+$/i,
    ~r/^(part|chapter)\s*\d+$/i
  ]

  @doc "Unique string key identifying this source."
  @impl true
  def key, do: "comic_vine"

  @doc "Human-readable source name shown in the UI."
  @impl true
  def name, do: "Comic Vine"

  @doc "Short description shown on the source configuration page."
  @impl true
  def description, do: "Large comic wiki by GameSpot. Requires a free API key."

  @doc "URL of the provider's API documentation."
  @impl true
  def homepage, do: "https://comicvine.gamespot.com/api/"

  @doc "String written into the `source` field of credits and external IDs."
  @impl true
  def information_source, do: "Comic Vine"

  @doc """
  Default rate limit: 3 requests per 60 seconds.

  The official limit is 200 requests per resource per hour (~3.3 req/min).
  Status 107 is returned on bursts before that ceiling is reached, so this
  cap is set below the theoretical maximum.
  """
  @impl true
  def default_rate_limit, do: {3, 60_000}

  @doc "Returns the list of user-supplied config fields required by this source."
  @impl true
  def config_schema do
    [
      %{key: "api_key", label: "API key", type: :secret, required: true, help: "comicvine.gamespot.com/api"}
    ]
  end

  @doc "Builds `Req` base options for all Comic Vine requests, injecting the API key."
  @impl true
  def req_options(config) do
    [
      base_url: "https://comicvine.gamespot.com/api",
      params: [api_key: config["api_key"], format: "json"]
    ]
  end

  @doc "Returns `true` only when Comic Vine responded with status code 1 (OK), skipping cache on error responses."
  @impl true
  def cacheable?(body), do: match?(%{"status_code" => 1}, body)

  # Wraps HTTP.get/3 and normalises the Comic Vine status_code envelope.
  # Status 107 (rate limited) is undocumented but observed; backs off 60 s.
  # Status 100 = invalid API key; 101 = object not found.
  defp cv_get(ctx, path, params, cache \\ nil) do
    case HTTP.get(ctx, path, params: params, cache: cache) do
      {:ok, %{"status_code" => 1, "results" => results}} -> {:ok, results}
      {:ok, %{"status_code" => 100}} -> {:error, :unauthorized}
      {:ok, %{"status_code" => 107}} -> {:error, {:rate_limited, 60_000}}
      {:ok, %{"status_code" => 101}} -> {:error, :not_found}
      {:ok, %{"error" => msg}} -> {:error, msg}
      {:ok, _} -> {:error, "Unexpected response"}
      error -> error
    end
  end

  @doc "Verifies the configured API key by hitting the lightweight `/types/` endpoint."
  @impl true
  def test_connection(ctx) do
    case cv_get(ctx, "/types/", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, HTTP.error_message(reason)}
    end
  end

  @doc """
  Searches Comic Vine volumes (series) by name.
  Returns a list of `Candidate` structs with `:kind` set to `:series`.
  """
  @impl true
  def search_series(query, ctx) do
    params = [query: query[:name], resources: "volume", limit: 20, field_list: Enum.join(@volume_fields, ",")]

    with {:ok, results} <- cv_get(ctx, "/search/", params, :short) do
      {:ok, Enum.map(results, &volume_candidate/1)}
    end
  end

  defp volume_candidate(v) do
    %Candidate{
      source_key: key(),
      kind: :series,
      id: to_string(v["id"]),
      series_id: to_string(v["id"]),
      series_name: v["name"],
      title: "#{v["name"]} (#{v["start_year"]})",
      year: int(v["start_year"]),
      issue_count: v["count_of_issues"],
      publisher: get_in(v, ["publisher", "name"]),
      cover_url: get_in(v, ["image", "small_url"]),
      url: v["site_detail_url"],
      raw: v
    }
  end

  @doc """
  Searches Comic Vine issues.

  When `query[:series_id]` is present the issues endpoint is filtered directly.
  Without a series ID, resolves up to two matching volumes first and merges
  their issue results — Comic Vine's issue search does not support filtering
  by series name alone.
  """
  @impl true
  def search_issues(query, ctx) do
    filters =
      [
        if(query[:series_id], do: "volume:#{query[:series_id]}"),
        if(query[:number], do: "issue_number:#{query[:number]}")
      ]
      |> Enum.reject(&is_nil/1)

    if blank?(query[:series_id]) do
      # Comic Vine can't filter issues by series name; resolve volumes first.
      with {:ok, volumes} <- search_series(%{name: query[:series_name]}, ctx) do
        volumes
        |> Enum.take(2)
        |> Enum.reduce_while({:ok, []}, fn v, {:ok, acc} ->
          case search_issues(Map.put(query, :series_id, v.id), ctx) do
            {:ok, issues} -> {:cont, {:ok, acc ++ issues}}
            error -> {:halt, error}
          end
        end)
      end
    else
      params = [filter: Enum.join(filters, ","), limit: 50, field_list: Enum.join(@issue_list_fields, ",")]

      with {:ok, results} <- cv_get(ctx, "/issues/", params, :short) do
        {:ok, Enum.map(results, &issue_candidate/1)}
      end
    end
  end

  defp issue_candidate(i) do
    cover_date = date(i["cover_date"])
    issue_name = if format_label?(i["name"]), do: nil, else: i["name"]

    %Candidate{
      source_key: key(),
      kind: :issue,
      id: to_string(i["id"]),
      series_id: get_in(i, ["volume", "id"]) && to_string(get_in(i, ["volume", "id"])),
      series_name: get_in(i, ["volume", "name"]),
      number: i["issue_number"],
      title: issue_name,
      year: year_of(cover_date),
      cover_url: get_in(i, ["image", "small_url"]),
      url: i["site_detail_url"],
      raw: i
    }
  end

  @doc """
  Fetches full issue detail from Comic Vine by its numeric ID.

  Calls `/issue/4000-<id>/` — Comic Vine single-object endpoints require a
  resource-type prefix (`4000` = issue). Returns a normalised metadata map
  via `issue_metadata/1`.
  """
  @impl true
  def fetch_issue(id, ctx) do
    with {:ok, i} when is_map(i) <-
           cv_get(ctx, "/issue/4000-#{id}/", [field_list: Enum.join(@issue_fields, ",")], :long) do
      {:ok, issue_metadata(i)}
    end
  end

  @doc """
  Maps a raw Comic Vine issue API response to a normalised metadata map.

  Exposed (not `@doc false`) so it can be called directly in tests without
  making a live HTTP request. Strips HTML from the description, normalises
  credits through `@roles`, and drops format-label titles (e.g. "TPB",
  "Vol. 1") so the volume name is used as the series title instead.
  """
  def issue_metadata(i) do
    cover_date = date(i["cover_date"])
    store_date = date(i["store_date"])
    volume = i["volume"] || %{}

    issue_name = if format_label?(i["name"]), do: nil, else: i["name"]

    %{}
    |> put(:series, volume["name"])
    |> put(:issue_number, decimal(i["issue_number"]))
    |> put(:title, issue_name)
    |> put(:stories, if(blank?(issue_name), do: [], else: [%{name: issue_name, external_id: nil}]))
    |> put(:cover_date, cover_date)
    |> put(:store_date, store_date)
    |> put(:year, year_of(cover_date) || year_of(store_date))
    |> put(:summary, strip_html(i["description"]))
    |> put(:credits, credits(i["person_credits"]))
    |> put(:characters, resources(i["character_credits"]))
    |> put(:teams, resources(i["team_credits"]))
    |> put(:locations, resources(i["location_credits"]))
    |> put(:arcs, Enum.map(resources(i["story_arc_credits"]), &Map.put(&1, :arc_number, nil)))
    |> put(:urls, if(i["site_detail_url"], do: [%{url: i["site_detail_url"], is_primary: false}], else: []))
    |> put(:cover_url, get_in(i, ["image", "original_url"]))
    |> put(:external_ids, [%{source: "Comic Vine", source_id: to_string(i["id"]), is_primary: false}])
    |> put(
      :series_external_ids,
      if(volume["id"], do: [%{source: "Comic Vine", source_id: to_string(volume["id"]), is_primary: false}])
    )
  end

  @roles %{
    "writer" => "Writer",
    "penciler" => "Penciller",
    "penciller" => "Penciller",
    "inker" => "Inker",
    "colorist" => "Colorist",
    "letterer" => "Letterer",
    "cover" => "Cover",
    "editor" => "Editor",
    "artist" => "Artist",
    "translator" => "Translator",
    "production" => "Production"
  }

  defp format_label?(nil), do: false

  defp format_label?(name) do
    normalized = name |> String.trim() |> String.downcase()
    normalized in @format_labels or Enum.any?(@format_label_patterns, &Regex.match?(&1, normalized))
  end

  defp credits(list) when is_list(list) do
    list
    |> Enum.reject(&blank?(&1["name"]))
    |> Enum.map(fn p ->
      roles =
        (p["role"] || "")
        |> String.split(",", trim: true)
        |> Enum.map(&Map.get(@roles, String.trim(String.downcase(&1)), "Other"))
        |> Enum.uniq()

      %{creator: p["name"], creator_id: to_string(p["id"]), roles: roles}
    end)
  end

  defp credits(_), do: []

  @doc """
  Fetches volume (series) detail from Comic Vine by its numeric ID.

  Calls `/volume/4050-<id>/` — `4050` is the Comic Vine resource-type prefix
  for volumes.
  """
  @impl true
  def fetch_series(id, ctx) do
    with {:ok, v} when is_map(v) <-
           cv_get(ctx, "/volume/4050-#{id}/", [field_list: Enum.join(@volume_fields, ",")], :long) do
      {:ok,
       %{}
       |> put(:name, v["name"])
       |> put(:start_year, int(v["start_year"]))
       |> put(:issue_count, v["count_of_issues"])
       |> put(:summary, strip_html(v["description"]))
       |> put(:publisher, get_in(v, ["publisher", "name"]))
       |> put(:external_ids, [%{source: "Comic Vine", source_id: to_string(v["id"]), is_primary: false}])}
    end
  end
end
