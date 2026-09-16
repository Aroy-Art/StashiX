defmodule StashixWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    :telemetry.attach(
      "stashix-longpoll-fallback",
      [:phoenix, :socket_connected],
      &__MODULE__.handle_socket_connected/4,
      nil
    )

    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def handle_socket_connected(_event, _measurements, %{transport: :longpoll} = meta, _config) do
    Logger.warning("LiveView client fell back to long polling",
      user_socket: inspect(meta.user_socket),
      result: meta.result
    )
  end

  def handle_socket_connected(_event, _measurements, _meta, _config), do: :ok

  def metrics do
    [
      # Phoenix Metrics
      distribution("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000]]
      ),
      distribution("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000]]
      ),
      distribution("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000]]
      ),
      distribution("phoenix.socket_connected.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500]]
      ),
      counter("phoenix.socket_connected.count",
        tags: [:transport],
        description: "Socket connections by transport type (websocket vs longpoll)"
      ),
      sum("phoenix.socket_drain.count"),
      distribution("phoenix.channel_joined.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500]]
      ),
      distribution("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 25, 50, 100, 250]]
      ),

      # Database Metrics
      distribution("stashix.repo.query.total_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250, 500]]
      ),
      distribution("stashix.repo.query.query_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [5, 10, 25, 50, 100, 250]]
      ),
      distribution("stashix.repo.query.queue_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500]]
      ),
      distribution("stashix.repo.query.decode_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 25, 50]]
      ),
      distribution("stashix.repo.query.idle_time",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100]]
      ),

      # VM Metrics
      last_value("vm.memory.total", unit: {:byte, :kilobyte}),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {StashixWeb, :count_users, []}
    ]
  end
end
