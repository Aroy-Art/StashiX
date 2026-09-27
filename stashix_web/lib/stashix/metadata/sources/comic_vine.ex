defmodule Stashix.Metadata.Sources.ComicVine do
  @moduledoc """
  Comic Vine (comicvine.gamespot.com). Needs a free API key. The API allows 200
  requests per resource per hour and flags fast clients, so the default limit is
  deliberately low.
  """
  @behaviour Stashix.Metadata.Source

  import Stashix.Metadata.Sources.Helpers
  alias Stashix.Metadata.{Candidate, HTTP}

  @issue_list_fields ~w(id name issue_number cover_date store_date volume image site_detail_url)
  @issue_fields ~w(id name issue_number cover_date store_date description volume image site_detail_url
                   person_credits character_credits team_credits location_credits story_arc_credits
                   concept_credits aliases)
  @volume_fields ~w(id name start_year publisher count_of_issues image site_detail_url description)

  @impl true
  def key, do: "comic_vine"
  @impl true
  def name, do: "Comic Vine"
  @impl true
  def description, do: "Large comic wiki by GameSpot. Requires a free API key."
  @impl true
  def homepage, do: "https://comicvine.gamespot.com/api/"
  @impl true
  def information_source, do: "Comic Vine"
  @impl true
  def default_rate_limit, do: {3, 60_000}

  @impl true
  def config_schema do
    [
      %{key: "api_key", label: "API key", type: :secret, required: true, help: "comicvine.gamespot.com/api"}
    ]
  end

  @impl true
  def req_options(config) do
    [
      base_url: "https://comicvine.gamespot.com/api",
      params: [api_key: config["api_key"], format: "json"]
    ]
  end

  defp cv_get(ctx, path, params) do
    case HTTP.get(ctx, path, params: params) do
      {:ok, %{"status_code" => 1, "results" => results}} -> {:ok, results}
      {:ok, %{"status_code" => 100}} -> {:error, :unauthorized}
      {:ok, %{"status_code" => 107}} -> {:error, {:rate_limited, 60_000}}
      {:ok, %{"status_code" => 101}} -> {:error, :not_found}
      {:ok, %{"error" => msg}} -> {:error, msg}
      {:ok, _} -> {:error, "Unexpected response"}
      error -> error
    end
  end

  @impl true
  def test_connection(ctx) do
    case cv_get(ctx, "/types/", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, HTTP.error_message(reason)}
    end
  end

  @impl true
  def search_series(query, ctx) do
    params = [query: query[:name], resources: "volume", limit: 20, field_list: Enum.join(@volume_fields, ",")]

    with {:ok, results} <- cv_get(ctx, "/search/", params) do
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

      with {:ok, results} <- cv_get(ctx, "/issues/", params) do
        {:ok, Enum.map(results, &issue_candidate/1)}
      end
    end
  end

  defp issue_candidate(i) do
    cover_date = date(i["cover_date"])

    %Candidate{
      source_key: key(),
      kind: :issue,
      id: to_string(i["id"]),
      series_id: get_in(i, ["volume", "id"]) && to_string(get_in(i, ["volume", "id"])),
      series_name: get_in(i, ["volume", "name"]),
      number: i["issue_number"],
      title: i["name"],
      year: year_of(cover_date),
      cover_url: get_in(i, ["image", "small_url"]),
      url: i["site_detail_url"],
      raw: i
    }
  end

  @impl true
  def fetch_issue(id, ctx) do
    with {:ok, i} when is_map(i) <- cv_get(ctx, "/issue/4000-#{id}/", field_list: Enum.join(@issue_fields, ",")) do
      {:ok, issue_metadata(i)}
    end
  end

  @doc false
  def issue_metadata(i) do
    cover_date = date(i["cover_date"])
    store_date = date(i["store_date"])
    volume = i["volume"] || %{}

    %{}
    |> put(:series, volume["name"])
    |> put(:issue_number, decimal(i["issue_number"]))
    |> put(:title, i["name"])
    |> put(:stories, if(blank?(i["name"]), do: [], else: [%{name: i["name"], external_id: nil}]))
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

  @impl true
  def fetch_series(id, ctx) do
    with {:ok, v} when is_map(v) <- cv_get(ctx, "/volume/4050-#{id}/", field_list: Enum.join(@volume_fields, ",")) do
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
