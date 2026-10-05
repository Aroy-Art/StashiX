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

    :telemetry.attach_many(
      "stashix-live-view-timing",
      [
        [:phoenix, :live_view, :mount, :start],
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_params, :start],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :handle_event, :start],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :render, :start],
        [:phoenix, :live_view, :render, :stop],
        [:phoenix, :live_component, :update, :start],
        [:phoenix, :live_component, :update, :stop],
        [:phoenix, :live_component, :handle_event, :start],
        [:phoenix, :live_component, :handle_event, :stop],
        [:stashix, :repo, :query]
      ],
      &__MODULE__.handle_live_view_timing/4,
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

  # Page load timing. Every LiveView callback is a span; the Repo query events
  # that fire inside one (same process) are summed into it, so a log line says
  # both how long the callback took and how much of that was the database.
  #
  # mount and handle_params are what a page load waits on, so they are always
  # logged. Events, renders and component updates only show up when slow.
  @db_key :stashix_live_view_db

  # Spans nest (a component update runs inside a render), so the totals are a
  # stack: queries count towards the innermost span and roll up into its parents.
  def handle_live_view_timing([:stashix, :repo, :query], measurements, _meta, _config) do
    case Process.get(@db_key) do
      [{count, time} | rest] ->
        Process.put(@db_key, [{count + 1, time + Map.get(measurements, :total_time, 0)} | rest])

      _ ->
        :ok
    end
  end

  def handle_live_view_timing([:phoenix, _, _, :start], _measurements, _meta, _config) do
    Process.put(@db_key, [{0, 0} | Process.get(@db_key) || []])
  end

  def handle_live_view_timing([:phoenix, kind, phase, :stop], measurements, meta, _config) do
    {queries, db_time} =
      case Process.get(@db_key) do
        [{count, time}, {parent_count, parent_time} | rest] ->
          Process.put(@db_key, [{parent_count + count, parent_time + time} | rest])
          {count, time}

        [totals] ->
          Process.delete(@db_key)
          totals

        _ ->
          {0, 0}
      end

    ms = System.convert_time_unit(measurements.duration, :native, :microsecond) / 1000
    slow? = ms >= slow_ms()

    if slow? or phase in [:mount, :handle_params] do
      db_ms = System.convert_time_unit(db_time, :native, :microsecond) / 1000

      Logger.log(if(slow?, do: :warning, else: :info), fn ->
        [
          "[timing] ",
          timing_label(kind, phase, meta),
          " ",
          format_ms(ms),
          " db=",
          format_ms(db_ms),
          " queries=",
          Integer.to_string(queries)
        ]
      end)
    end
  end

  defp slow_ms, do: Application.get_env(:stashix, :slow_live_view_ms, 200)

  defp format_ms(ms), do: [:erlang.float_to_binary(ms, decimals: 1), "ms"]

  defp timing_label(:live_view, :mount, %{socket: socket}) do
    ["mount ", inspect(socket.view), " connected=", to_string(Phoenix.LiveView.connected?(socket))]
  end

  defp timing_label(:live_view, :handle_params, %{socket: socket, uri: uri}) do
    ["handle_params ", inspect(socket.view), " ", URI.parse(uri).path || "/"]
  end

  defp timing_label(:live_view, :handle_event, %{socket: socket, event: event}) do
    ["handle_event ", inspect(socket.view), " ", inspect(event)]
  end

  defp timing_label(:live_component, phase, %{component: component} = meta) do
    event = if meta[:event], do: [" ", inspect(meta.event)], else: []
    [to_string(phase), " ", inspect(component), event]
  end

  defp timing_label(_kind, phase, %{socket: socket}) do
    [to_string(phase), " ", inspect(socket.view)]
  end

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
