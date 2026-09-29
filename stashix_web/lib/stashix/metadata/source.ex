defmodule Stashix.Metadata.Source do
  @moduledoc """
  Behaviour for external metadata source plugins (Metron, Comic Vine, GCD, ...).

  A source is a module implementing these callbacks and listed under
  `config :stashix, :metadata_sources`. Enabling, priority, rate limit and the
  source's own config (credentials, cookies, ...) are stored per source in
  `metadata_sources` and edited from `/admin/metadata`.

  ## Metadata shapes

  `fetch_issue/2` returns the same map `Stashix.Metadata.Parser` produces from a
  MetronInfo.xml (`:series`, `:issue_number`, `:cover_date`, `:summary`,
  `:credits`, `:characters`, `:external_ids`, ...), plus optionally `:title`
  and `:cover_url`.

  `fetch_series/2` returns a series map: `:name`, `:sort_name`, `:volume`,
  `:format`, `:start_year`, `:end_year`, `:issue_count`, `:summary`,
  `:publisher`, `:language`, `:external_ids`.

  Both `:external_ids` lists should include the source's own id, e.g.
  `%{source: "Metron", source_id: "1234", is_primary: true}`.
  """

  alias Stashix.Metadata.Candidate

  @typedoc "Runtime context passed to every call: decrypted config + ready Req client."
  @type ctx :: %{config: map(), req: Req.Request.t(), source_key: String.t()}

  @type field_type :: :string | :secret | :integer | :boolean | :cookies
  @type config_field :: %{
          required(:key) => String.t(),
          required(:label) => String.t(),
          required(:type) => field_type(),
          optional(:required) => boolean(),
          optional(:help) => String.t(),
          optional(:default) => term()
        }

  @type series_query :: %{
          optional(:name) => String.t(),
          optional(:year) => integer() | nil,
          optional(:publisher) => String.t() | nil
        }

  @type issue_query :: %{
          optional(:series_id) => String.t() | nil,
          optional(:series_name) => String.t() | nil,
          optional(:number) => String.t() | nil,
          optional(:year) => integer() | nil
        }

  @doc "Stable identifier stored in the DB, e.g. \"metron\"."
  @callback key() :: String.t()
  @doc "Display name."
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback homepage() :: String.t()
  @doc "Value of the `information_source` enum used for external ids (\"Metron\", \"Comic Vine\", ...)."
  @callback information_source() :: String.t()
  @doc "Fields rendered in the admin settings form; `:secret`/`:cookies` values are encrypted and masked."
  @callback config_schema() :: [config_field()]
  @doc "Default rate limit as `{requests, per_milliseconds}`."
  @callback default_rate_limit() :: {pos_integer(), pos_integer()}
  @doc "Base Req options (base_url, auth, headers) built from the source config."
  @callback req_options(config :: map()) :: keyword()

  @callback test_connection(ctx()) :: :ok | {:error, String.t()}
  @callback search_series(series_query(), ctx()) :: {:ok, [Candidate.t()]} | {:error, term()}
  @callback search_issues(issue_query(), ctx()) :: {:ok, [Candidate.t()]} | {:error, term()}
  @callback fetch_issue(id :: String.t(), ctx()) :: {:ok, map()} | {:error, term()}
  @callback fetch_series(id :: String.t(), ctx()) :: {:ok, map()} | {:error, term()}

  @doc """
  Optional. Whether a successful (2xx) response body may be cached. Implement it
  for APIs that report errors inside a 200 response.
  """
  @callback cacheable?(body :: term()) :: boolean()

  @doc """
  Optional. Name of the endpoint a request hits (e.g. `"issues"`), or `nil`.
  Each endpoint gets its own hourly quota on top of the source-wide limit;
  implement together with `default_endpoint_limit_per_hour/0`.
  """
  @callback endpoint_scope(url :: URI.t()) :: String.t() | nil

  @doc "Optional. Default hourly request quota per endpoint (see `endpoint_scope/1`)."
  @callback default_endpoint_limit_per_hour() :: pos_integer()

  @doc """
  Optional. Hosts (or parent domains) the source serves images from. Cover
  URLs on these hosts are fetched through Stashix's image proxy.
  """
  @callback image_hosts() :: [String.t()]

  @optional_callbacks cacheable?: 1, endpoint_scope: 1, default_endpoint_limit_per_hour: 0, image_hosts: 0
end
