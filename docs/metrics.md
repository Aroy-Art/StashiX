# Metrics

Stashix exposes a [Prometheus](https://prometheus.io/) scrape endpoint on a dedicated port, separate from the main application port.

## Endpoint

```
GET http://<host>:9568/metrics
```

The endpoint returns metrics in the Prometheus text exposition format. It is served by a standalone Bandit listener and is completely independent of the main HTTP port — no Stashix authentication applies.

## Configuration

Set these in your application config or environment:

| Config key              | Env override | Default       | Purpose                              |
| ----------------------- | ------------ | ------------- | ------------------------------------ |
| `:metrics_port`         | —            | `9568`        | Port for the `/metrics` endpoint     |
| `:metrics_ip`           | —            | `{0,0,0,0}`  | Bind address (all interfaces)        |

Example — loopback only, custom port:

```elixir
# config/prod.exs
config :stashix, :metrics_port, 9568
config :stashix, :metrics_ip, {127, 0, 0, 1}
```

To lock the endpoint to a specific network interface or restrict it to localhost, set `:metrics_ip` to the desired IP tuple and use a firewall rule for external enforcement.

## Prometheus scrape config

```yaml
scrape_configs:
  - job_name: stashix
    static_configs:
      - targets: ["<host>:9568"]
    metrics_path: /metrics
```

## Available metrics

### Phoenix

| Metric | Type | Labels | Description |
| ------ | ---- | ------ | ----------- |
| `phoenix_endpoint_stop_duration_milliseconds` | Histogram | — | HTTP request duration |
| `phoenix_router_dispatch_stop_duration_milliseconds` | Histogram | `route` | Routed request duration per route |
| `phoenix_router_dispatch_exception_duration_milliseconds` | Histogram | `route` | Exception handler duration per route |
| `phoenix_socket_connected_duration_milliseconds` | Histogram | — | Socket connection handshake duration |
| `phoenix_socket_connected_count` | Counter | `transport` | Socket connections by transport type |
| `phoenix_socket_drain_count` | Counter | — | Drained socket count |
| `phoenix_channel_joined_duration_milliseconds` | Histogram | — | Channel join duration |
| `phoenix_channel_handled_in_duration_milliseconds` | Histogram | `event` | Channel event handler duration |

The `transport` label on `phoenix_socket_connected_count` is either `websocket` or `longpoll`. A rising `longpoll` count means clients cannot establish a WebSocket — typically a proxy misconfiguration (missing `Upgrade` header passthrough).

### Database

| Metric | Type | Description |
| ------ | ---- | ----------- |
| `stashix_repo_query_total_time_milliseconds` | Histogram | Total query time (sum of all phases) |
| `stashix_repo_query_query_time_milliseconds` | Histogram | Time executing the query |
| `stashix_repo_query_queue_time_milliseconds` | Histogram | Time waiting for a DB connection from the pool |
| `stashix_repo_query_decode_time_milliseconds` | Histogram | Time decoding the DB response |
| `stashix_repo_query_idle_time_milliseconds` | Histogram | Time the connection was idle before checkout |

### VM

| Metric | Type | Description |
| ------ | ---- | ----------- |
| `vm_memory_total_kilobytes` | Gauge | Total BEAM memory usage |
| `vm_total_run_queue_lengths_total` | Gauge | Total scheduler run queue length |
| `vm_total_run_queue_lengths_cpu` | Gauge | CPU scheduler run queue length |
| `vm_total_run_queue_lengths_io` | Gauge | IO scheduler run queue length |

## Grafana

Import the Prometheus data source then use these queries as a starting point:

```promql
# Longpoll fallback rate (clients that couldn't establish WebSocket)
increase(phoenix_socket_connected_count{transport="longpoll"}[5m])

# 95th-percentile HTTP request latency
histogram_quantile(0.95, rate(phoenix_router_dispatch_stop_duration_milliseconds_bucket[5m]))

# DB query queue saturation (p99)
histogram_quantile(0.99, rate(stashix_repo_query_queue_time_milliseconds_bucket[5m]))

# BEAM memory
vm_memory_total_kilobytes / 1024
```

## Long-poll fallback warnings

In addition to the counter metric, Stashix logs a `[warning]` line whenever a client connects via long polling:

```
[warning] LiveView client fell back to long polling user_socket=StashixWeb.UserSocket result=:ok
```

This fires once per socket connection, not per poll request. Common causes:
- Reverse proxy not forwarding `Connection: Upgrade` / `Upgrade: websocket` headers
- Load balancer with WebSocket support disabled
- Corporate firewall blocking `ws://` / `wss://`
