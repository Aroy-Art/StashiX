defmodule StashixWeb.Plugs.MetricsPlug do
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{path_info: ["metrics"]} = conn, _opts) do
    body = TelemetryMetricsPrometheus.Core.scrape()

    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(200, body)
  end

  def call(conn, _opts) do
    Plug.Conn.send_resp(conn, 404, "not found")
  end
end
