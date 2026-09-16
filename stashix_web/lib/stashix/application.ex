defmodule Stashix.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    metrics_port = Application.get_env(:stashix, :metrics_port, 9568)
    metrics_ip = Application.get_env(:stashix, :metrics_ip, {0, 0, 0, 0})

    children = [
      TwMerge.Cache,
      StashixWeb.Telemetry,
      {TelemetryMetricsPrometheus.Core, metrics: StashixWeb.Telemetry.metrics()},
      Stashix.Repo,
      {DNSCluster, query: Application.get_env(:stashix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Stashix.PubSub},
      Stashix.Scanner.Supervisor,
      StashixWeb.Endpoint,
      {Bandit, plug: StashixWeb.Plugs.MetricsPlug, scheme: :http, ip: metrics_ip, port: metrics_port}
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
