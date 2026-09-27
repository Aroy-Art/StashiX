defmodule Stashix.Metadata.Cache do
  @moduledoc """
  Persistent cache of metadata source API responses (successful GETs only).

  Wired into every source's Req client by `Stashix.Metadata.HTTP`: a hit skips
  both the network and the rate limiter. Searches use a short TTL, detail
  lookups a long one (see the metadata settings).
  """
  use Ecto.Schema
  import Ecto.Query

  alias Stashix.Repo

  @primary_key {:key, :string, autogenerate: false}

  schema "metadata_cache" do
    field :source_key, :string
    field :url, :string
    field :body, :map
    field :expires_at, :naive_datetime

    timestamps()
  end

  # Query params that carry credentials never become part of the key or stored URL.
  @secret_params ~w(api_key apikey key token access_token)

  @doc "Cache key and credential-free URL for a request URI."
  def key(source_key, %URI{} = uri) do
    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.drop(@secret_params)
      |> Enum.sort()
      |> URI.encode_query()

    url = URI.to_string(%{uri | query: if(query == "", do: nil, else: query)})
    {:crypto.hash(:sha256, source_key <> " " <> url) |> Base.encode16(case: :lower), url}
  end

  def get(key) do
    now = NaiveDateTime.utc_now()

    case Repo.one(from c in __MODULE__, where: c.key == ^key and c.expires_at > ^now, select: c.body) do
      %{"b" => body} -> {:ok, body}
      _ -> :miss
    end
  end

  def put(key, source_key, url, body, ttl_seconds) do
    now = NaiveDateTime.utc_now(:second)

    row = %{
      key: key,
      source_key: source_key,
      url: url,
      body: %{"b" => body},
      expires_at: NaiveDateTime.add(now, ttl_seconds),
      inserted_at: now,
      updated_at: now
    }

    Repo.insert_all(__MODULE__, [row],
      on_conflict: {:replace, [:body, :expires_at, :updated_at]},
      conflict_target: :key
    )

    :ok
  rescue
    # Never fail a lookup because the cache write failed (e.g. odd JSON)
    _ -> :ok
  end

  def clear(source_key \\ nil) do
    q = if source_key, do: from(c in __MODULE__, where: c.source_key == ^source_key), else: __MODULE__
    {n, _} = Repo.delete_all(q)
    n
  end

  def prune do
    now = NaiveDateTime.utc_now()
    {n, _} = Repo.delete_all(from c in __MODULE__, where: c.expires_at <= ^now)
    n
  end

  def count, do: Repo.aggregate(__MODULE__, :count)
end
