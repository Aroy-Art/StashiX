# Metrics

The operator guide (endpoint, scrape config, metric list, Grafana queries,
log lines) is on the docs site:
[Monitoring](https://stashix.net/docs/admin-guide/monitoring/). This page
covers the config and code behind it.

## Listener

`Stashix.Application` starts a standalone Bandit listener for
`StashixWeb.Plugs.MetricsPlug`, separate from the endpoint. No Stashix
authentication applies.

| Config key              | Env override | Default      | Purpose                          |
| ----------------------- | ------------ | ------------ | -------------------------------- |
| `:metrics_port`         | —            | `9568`       | Port for the `/metrics` endpoint |
| `:metrics_ip`           | —            | `{0,0,0,0}`  | Bind address (all interfaces)    |
| `:slow_live_view_ms`    | —            | `200`        | Threshold for slow-callback logs |

```elixir
# config/prod.exs
config :stashix, :metrics_port, 9568
config :stashix, :metrics_ip, {127, 0, 0, 1}
config :stashix, :slow_live_view_ms, 200
```

None of these has an env override, so Docker users control access with the
Compose port mapping only.

## Metric definitions

Metrics are defined in `StashixWeb.Telemetry`. Names carry no unit suffix;
durations are in milliseconds, `vm_memory_total` in kilobytes.

The `stashix_live_view_callback_*` metrics and the `[timing]` log lines are
attributed per callback process. Queries run in other processes
(`assign_async`, tasks) are not attributed to a callback.

`mount` and `handle_params` are always logged at `[info]`; events, renders and
component updates only past `:slow_live_view_ms`, at `[warning]`. Long-poll
connections log one `[warning]` per socket.

When adding a metric, also add it to the table on the docs site.
