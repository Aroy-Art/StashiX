defmodule Stashix.Metadata.HTTP do
  @moduledoc """
  Builds the Req client handed to source plugins and normalises responses.

  Every request passes through the source's rate limiter. Cookies from a
  `:cookies` config field are sent as a `cookie` header.
  """
  alias Stashix.Metadata.{RateLimiter, Sources}

  @version Mix.Project.config()[:version]

  @doc "Runtime context for a `%{module: mod, config: %SourceConfig{}}` entry."
  def context(%{module: mod, config: row}) do
    config = row.config || %{}
    limit = Sources.rate_limit(mod, row)
    key = mod.key()

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
      |> Req.Request.append_request_steps(rate_limit: &rate_limit_step(&1, key, limit))
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

  defp rate_limit_step(request, key, limit) do
    case RateLimiter.acquire(key, limit) do
      :ok -> request
      {:error, reason} -> {request, %Stashix.Metadata.HTTP.Error{reason: reason}}
    end
  end

  @doc """
  GET returning `{:ok, body}` or a normalised error:
  `:unauthorized`, `:not_found`, `{:rate_limited, ms}`, `{:http, status}`, `{:transport, reason}`.
  """
  def get(%{req: req}, url, opts \\ []) do
    req
    |> Req.get([url: url] ++ opts)
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
