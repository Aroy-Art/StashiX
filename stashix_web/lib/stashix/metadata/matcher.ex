defmodule Stashix.Metadata.Matcher do
  @moduledoc """
  Finds the best external match for a book or series.

  For each enabled source (by priority) it uses a stored external id when the
  book/series already has one, otherwise searches the source and scores the
  results against what we know locally (series name, number, year, publisher).
  The first source that yields a confident match wins; otherwise all scored
  candidates are returned for manual review.
  """
  import Ecto.Query

  alias Stashix.Repo
  alias Stashix.Library.{Book, Series}
  alias Stashix.Metadata.{Candidate, HTTP, Sources}

  @max_series_tried 3
  @max_candidates 15

  @type result ::
          {:matched, source :: map(), Candidate.t()}
          | {:review, query :: map(), [Candidate.t()]}
          | {:error, term()}

  ## Queries

  @doc "Local search query for a book."
  def book_query(%Book{} = book) do
    book = Repo.preload(book, [:publishers, :external_ids, series: [:publishers, :external_ids]])
    series = book.series

    %{
      "series_name" => (series && series.name) || book.title,
      "number" => format_number(book.issue_number) || if(is_nil(series), do: "1"),
      "year" => book.year || (series && series.start_year),
      "series_year" => series && series.start_year,
      "publisher" => first_publisher(book.publishers) || (series && first_publisher(series.publishers)),
      "page_count" => book.page_count
    }
  end

  @doc "Local search query for a series."
  def series_query(%Series{} = series) do
    series = Repo.preload(series, [:publishers])

    %{
      "series_name" => series.name,
      "year" => series.start_year,
      "series_year" => series.start_year,
      "publisher" => first_publisher(series.publishers)
    }
  end

  defp first_publisher([%{name: name} | _]), do: name
  defp first_publisher(_), do: nil

  def format_number(nil), do: nil
  def format_number(%Decimal{} = d), do: d |> Decimal.normalize() |> Decimal.to_string(:normal)
  def format_number(n), do: to_string(n)

  ## Book matching

  @doc "Runs automatic matching for a book."
  @spec match_book(Book.t(), map()) :: result()
  def match_book(%Book{} = book, settings) do
    book = Repo.preload(book, [:external_ids, series: :external_ids])
    query = book_query(book)

    run_sources(query, settings, fn source, ctx ->
      case known_id(book.external_ids, source.module) do
        nil ->
          series_id = book.series && known_id(book.series.external_ids, source.module)
          search_book(source, ctx, query, series_id, settings)

        id ->
          {:ok, [%Candidate{source_key: source.module.key(), kind: :issue, id: id, score: 1.0}]}
      end
    end)
  end

  @doc "Runs automatic matching for a series (series-level record only)."
  @spec match_series(Series.t(), map()) :: result()
  def match_series(%Series{} = series, settings) do
    series = Repo.preload(series, :external_ids)
    query = series_query(series)

    run_sources(query, settings, fn source, ctx ->
      case known_id(series.external_ids, source.module) do
        nil ->
          with {:ok, candidates} <- search_series(source, ctx, query) do
            {:ok, candidates}
          end

        id ->
          {:ok, [%Candidate{source_key: source.module.key(), kind: :series, id: id, series_id: id, score: 1.0}]}
      end
    end)
  end

  defp run_sources(query, settings, fun) do
    sources = Enum.filter(Sources.enabled(), &Sources.configured?(&1.module, &1.config.config))

    if sources == [] do
      {:error, :no_sources}
    else
      Enum.reduce_while(sources, {[], []}, fn source, {all, errors} ->
        ctx = HTTP.context(source)

        case fun.(source, ctx) do
          {:ok, candidates} ->
            candidates = Enum.sort_by(candidates, & &1.score, :desc)

            if confident?(candidates, settings) and source.config.auto_apply do
              {:halt, {:matched, source, hd(candidates)}}
            else
              {:cont, {all ++ candidates, errors}}
            end

          {:error, {:rate_limited, _} = reason} ->
            # Propagate so the job snoozes instead of reviewing a partial result.
            {:halt, {:error, reason}}

          {:error, reason} ->
            {:cont, {all, [{source.module.key(), reason} | errors]}}
        end
      end)
      |> case do
        {:matched, _, _} = matched ->
          matched

        {:error, _} = error ->
          error

        {[], [_ | _] = errors} ->
          {:error, {:sources_failed, errors}}

        {candidates, _errors} ->
          {:review, query, candidates |> Enum.sort_by(& &1.score, :desc) |> Enum.take(@max_candidates)}
      end
    end
  end

  @doc "True when the top candidate clears the threshold and leads the runner-up by the margin."
  def confident?([], _), do: false

  def confident?([top | rest], settings) do
    threshold = settings["auto_match_threshold"] || 0.9
    margin = settings["auto_match_margin"] || 0.1

    top.score >= threshold and
      case rest do
        [] -> true
        [second | _] -> top.score - second.score >= margin
      end
  end

  defp known_id(external_ids, mod) when is_list(external_ids) do
    source = mod.information_source()
    Enum.find_value(external_ids, fn e -> if to_string(e.source) == source, do: e.source_id end)
  end

  defp known_id(_, _), do: nil

  defp search_book(source, ctx, query, nil, settings) do
    with {:ok, series_candidates} <- search_series(source, ctx, query) do
      series_candidates = Enum.sort_by(series_candidates, & &1.score, :desc)

      tried =
        if confident?(series_candidates, settings),
          do: [hd(series_candidates)],
          else: Enum.take(series_candidates, @max_series_tried)

      tried
      |> Enum.reduce_while({:ok, []}, fn series, {:ok, acc} ->
        case issues_for_series(source, ctx, query, series.id, series.score) do
          {:ok, issues} -> {:cont, {:ok, acc ++ issues}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp search_book(source, ctx, query, series_id, _settings) do
    issues_for_series(source, ctx, query, series_id, 1.0)
  end

  defp issues_for_series(source, ctx, query, series_id, series_score) do
    issue_query = %{series_id: series_id, number: query["number"], year: query["year"]}

    with {:ok, issues} <- source.module.search_issues(issue_query, ctx) do
      {:ok, Enum.map(issues, &%{&1 | score: score_issue(&1, query, series_score)})}
    end
  end

  defp search_series(source, ctx, query) do
    series_query = %{name: query["series_name"], year: query["series_year"], publisher: query["publisher"]}

    with {:ok, results} <- source.module.search_series(series_query, ctx) do
      {:ok, Enum.map(results, &%{&1 | score: score_series(&1, query)})}
    end
  end

  @doc """
  Manual search from the Identify dialog: scored candidates from one source.
  `refresh: true` bypasses the response cache.
  """
  def search(source_key, kind, query, opts \\ []) do
    with %{} = source <- Sources.get(source_key) || {:error, :unknown_source},
         ctx = HTTP.context(source, refresh: Keyword.get(opts, :refresh, false)) do
      case kind do
        :series ->
          search_series(source, ctx, query)

        :issue ->
          with {:ok, results} <- search_series(source, ctx, query) do
            results
            |> Enum.sort_by(& &1.score, :desc)
            |> Enum.take(@max_series_tried)
            |> Enum.reduce_while({:ok, []}, fn s, {:ok, acc} ->
              case issues_for_series(source, ctx, query, s.id, s.score) do
                {:ok, issues} -> {:cont, {:ok, acc ++ issues}}
                error -> {:halt, error}
              end
            end)
          end

        {:series_id, series_id} ->
          issues_for_series(source, ctx, query, series_id, 1.0)
      end
      |> case do
        {:ok, list} -> {:ok, Enum.sort_by(list, & &1.score, :desc)}
        error -> error
      end
    end
  end

  ## Scoring

  @doc "Score 0..1 for an issue candidate. `series_score` is the parent series match score."
  def score_issue(%Candidate{} = c, query, series_score) do
    name = if c.series_name, do: name_similarity(c.series_name, query["series_name"]), else: series_score
    name = max(name, series_score)

    0.5 * name +
      0.3 * number_score(c.number, query["number"]) +
      0.15 * year_score(c.year, query["year"]) +
      0.05 * text_score(c.publisher, query["publisher"])
  end

  @doc "Score 0..1 for a series candidate."
  def score_series(%Candidate{} = c, query) do
    0.7 * name_similarity(c.series_name, query["series_name"]) +
      0.2 * year_score(c.year, query["series_year"] || query["year"]) +
      0.1 * text_score(c.publisher, query["publisher"])
  end

  def name_similarity(a, b) when is_binary(a) and is_binary(b) do
    na = normalize_name(a)
    nb = normalize_name(b)

    cond do
      na == "" or nb == "" -> 0.0
      na == nb -> 1.0
      true -> String.jaro_distance(na, nb) * 0.95
    end
  end

  def name_similarity(_, _), do: 0.0

  def normalize_name(name) do
    name
    |> String.downcase()
    |> String.replace("&", " and ")
    |> Stashix.Metadata.Sources.Helpers.strip_year_suffix()
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/^\s*the\s+/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_number(nil), do: nil

  def normalize_number(n) do
    n = n |> to_string() |> String.trim() |> String.downcase() |> String.trim_leading("#")

    case Decimal.parse(n) do
      {d, ""} -> d |> Decimal.normalize() |> Decimal.to_string(:normal)
      _ -> String.trim_leading(n, "0")
    end
  end

  defp number_score(a, b) do
    case {normalize_number(a), normalize_number(b)} do
      {nil, _} -> 0.5
      {_, nil} -> 0.5
      {x, x} -> 1.0
      _ -> 0.0
    end
  end

  defp year_score(a, b) when is_integer(a) and is_integer(b) do
    case abs(a - b) do
      0 -> 1.0
      1 -> 0.7
      2 -> 0.3
      _ -> 0.0
    end
  end

  defp year_score(_, _), do: 0.5

  defp text_score(a, b) when is_binary(a) and is_binary(b) do
    if name_similarity(a, b) > 0.85, do: 1.0, else: 0.0
  end

  defp text_score(_, _), do: 0.5

  @doc "Book ids of a series, for fan-out matching."
  def series_book_ids(series_id, opts \\ []) do
    from(b in Book,
      where: b.series_id == ^series_id and is_nil(b.deleted_at),
      select: b.id
    )
    |> maybe_skip_locked(opts)
    |> maybe_skip_matched(opts)
    |> Repo.all()
  end

  defp maybe_skip_locked(q, opts) do
    if Keyword.get(opts, :skip_locked, true), do: where(q, [b], not b.metadata_locked), else: q
  end

  defp maybe_skip_matched(q, opts) do
    if Keyword.get(opts, :skip_matched, false), do: where(q, [b], is_nil(b.metadata_matched_at)), else: q
  end
end
