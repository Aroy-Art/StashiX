defmodule StashixWeb.Plugs.RequestLogger do
  require Logger
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time()

    Plug.Conn.register_before_send(conn, fn conn ->
      duration_ms = System.convert_time_unit(System.monotonic_time() - start, :native, :millisecond)
      ip = conn.remote_ip |> :inet.ntoa() |> List.to_string()

      Logger.info("#{conn.method} #{conn.request_path} #{conn.status} ip=#{ip} #{duration_ms}ms")

      conn
    end)
  end
end
