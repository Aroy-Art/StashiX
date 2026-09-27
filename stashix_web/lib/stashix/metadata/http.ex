defmodule Stashix.Metadata.HTTP do
  @moduledoc """
  Builds the Req client handed to source plugins and normalises responses.

  Every request passes through the source's rate limiter. Cookies from a
  `:cookies` config field are sent as a `cookie` header.
  """
  alias Stashix.Metadata.{RateLimiter, Sources}

  @version Mix.Project.config()[:version]

  @doc """
  Runtime context for a `%{module: mod, config: %SourceConfig{}}` entry.

  Options:
    * `:refresh` - skip cache reads (responses are still stored)
  """
  def context(%{module: mod, config: row}, opts \\ []) do
    config = row.config || %{}
    limit = Sources.rate_limit(mod, row)
    key = mod.key()
    cache = cache_config(Keyword.get(opts, :refresh, false))

    req =
      Req.new(
        user_agent: "Stashix/#{@version} (+https://git.aroy-art.com/Aroy/Stashix)",
        retry: :transient,
        max_retries: 2,
        retry_delay: fn n -> min(Integer.pow(2, n) * 1_000, 10_000) end,
        receive_timeout: 30_000,
        # Django REST framework APIs (GCD) serve HTML unless JSON is requested
        headers: [accept: "application/json"]
      )
      |> Req.merge(mod.req_options(config))
      |> put_cookies(mod, config)
      |> Req.Request.register_options([:metadata_cache])
      |> Req.Request.append_request_steps(
        metadata_cache: &cache_request_step(&1, key, cache),
        rate_limit: &rate_limit_step(&1, key, limit)
      )
      |> Req.Request.append_response_steps(metadata_cache: &cache_response_step(&1, mod, cache))
      |> Req.merge(Application.get_env(:stashix, :metadata_req_options, []))

    %{config: config, req: req, source_key: key}
  end

  defp put_cookies(req, mod, config) do
    cookie =
      mod.config_schema()
      |> Enum.filter(&(&1.type == :cookies))
      |> Enum.map(&Map.get(config, &1.key))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.map(&normalize_cookies/1)
      |> Enum.join("; ")

    if cookie == "", do: req, else: Req.Request.put_header(req, "cookie", cookie)
  end

  # Accept "a=1; b=2", one cookie per line, or Netscape cookies.txt lines.
  defp normalize_cookies(raw) do
    raw
    |> String.split(["\n", ";"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(fn line ->
      case String.split(line, "\t") do
        [_domain, _flag, _path, _secure, _expiry, name, value] -> "#{name}=#{value}"
        _ -> line
      end
    end)
    |> Enum.join("; ")
  end

  defp cache_config(refresh) do
    settings = Stashix.Settings.metadata()

    %{
      refresh: refresh,
      ttl: %{
        short: round((settings["cache_search_hours"] || 24) * 3600),
        long: round((settings["cache_detail_days"] || 30) * 86_400)
      }
    }
  end

  # Requests made with `metadata_cache: :short | :long` are served from / stored in
  # Stashix.Metadata.Cache. A hit halts the pipeline before the rate limiter.
  defp cache_request_step(request, source_key, cache) do
    with kind when kind in [:short, :long] <- request.options[:metadata_cache],
         :get <- request.method,
         true <- cache.ttl[kind] > 0 do
      {cache_key, url} = Stashix.Metadata.Cache.key(source_key, request.url)
      request = Req.Request.put_private(request, :metadata_cache, {cache_key, url, kind})

      case if(cache.refresh, do: :miss, else: Stashix.Metadata.Cache.get(cache_key)) do
        {:ok, body} ->
          response = Req.Response.new(status: 200, body: body) |> Req.Response.put_private(:cached, true)
          {request, response}

        :miss ->
          request
      end
    else
      _ -> request
    end
  end

  defp cache_response_step({request, response}, mod, cache) do
    with {cache_key, url, kind} <- Req.Request.get_private(request, :metadata_cache),
         status when status in 200..299 <- response.status,
         false <- Req.Response.get_private(response, :cached, false),
         body when is_map(body) or is_list(body) <- response.body,
         true <- not function_exported?(mod, :cacheable?, 1) or mod.cacheable?(body) do
      Stashix.Metadata.Cache.put(cache_key, mod.key(), url, body, cache.ttl[kind])
    end

    {request, response}
  end

  defp rate_limit_step(request, key, limit) do
    case RateLimiter.acquire(key, limit) do
      :ok -> request
      {:error, reason} -> {request, %Stashix.Metadata.HTTP.Error{reason: reason}}
    end
  end

  @doc """
  GET returning `{:ok, body}` or a normalised error:
  `:unauthorized`, `:not_found`, `{:rate_limited, ms}`, `{:http, status}`, `{:transport, reason}`.

  Pass `cache: :short` (searches) or `cache: :long` (detail records) to use the
  response cache.
  """
  def get(%{req: req}, url, opts \\ []) do
    {cache, opts} = Keyword.pop(opts, :cache)

    req
    |> Req.get([url: url, metadata_cache: cache] ++ opts)
    |> normalize()
  end

  defp normalize({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp normalize({:ok, %Req.Response{status: status}}) when status in [401, 403],
    do: {:error, :unauthorized}

  defp normalize({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}

  defp normalize({:ok, %Req.Response{status: 429} = resp}) do
    secs =
      case Req.Response.get_header(resp, "retry-after") do
        [v | _] ->
          case Integer.parse(v) do
            {i, _} -> i
            :error -> 60
          end

        _ ->
          60
      end

    {:error, {:rate_limited, secs * 1_000}}
  end

  defp normalize({:ok, %Req.Response{status: status}}), do: {:error, {:http, status}}
  defp normalize({:error, %Stashix.Metadata.HTTP.Error{reason: reason}}), do: {:error, reason}
  defp normalize({:error, exception}), do: {:error, {:transport, Exception.message(exception)}}

  @doc "Human readable message for a normalised error."
  def error_message(:unauthorized), do: "Authentication failed (check credentials/cookies)"
  def error_message(:not_found), do: "Not found"
  def error_message({:rate_limited, ms}), do: "Rate limited, retry in #{div(ms, 1000)}s"
  def error_message({:http, status}), do: "HTTP #{status}"
  def error_message({:transport, msg}), do: "Connection error: #{msg}"
  def error_message(:not_configured), do: "Source is not configured"
  def error_message(other) when is_binary(other), do: other
  def error_message(other), do: inspect(other)
end
