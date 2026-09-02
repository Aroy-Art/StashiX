defmodule Stashix.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TwMerge.Cache,
      StashixWeb.Telemetry,
      Stashix.Repo,
      {DNSCluster, query: Application.get_env(:stashix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Stashix.PubSub},
      Stashix.Scanner.Supervisor,
      StashixWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Stashix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    StashixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
