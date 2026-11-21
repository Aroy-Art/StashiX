# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Kobo.Store do
  @moduledoc """
  The proxy to Kobo's own store API (`storeapi.kobo.com`), so a Kobo pointed
  at Stashix keeps its Kobo account: the shop, wishlists and the books
  bought from Kobo still sync alongside the library's.

  The device's own Kobo credentials (its `Authorization` and `x-kobo-*`
  headers) go along; nothing of Stashix's does. On by default; off with
  `KOBO_PROXY=false` (`config :stashix, kobo_proxy: false`), and then those
  calls get an empty answer.
  """

  @base_url "https://storeapi.kobo.com"

  # Device headers Kobo needs, besides every x-kobo-* one. The sync token
  # is Stashix's own and is swapped for Kobo's by the caller.
  @forward ~w(authorization user-agent accept-language)
  @not_forwarded ~w(x-kobo-synctoken)

  def enabled?, do: Application.get_env(:stashix, :kobo_proxy, true) != false

  @doc """
  Sends a request on to Kobo. `headers` are the device's request headers
  (filtered here); `extra` are added as they are. Returns
  `{:ok, %{status, headers, body}}` with Kobo's `x-kobo-*` headers and the
  raw body, or `{:error, reason}`.
  """
  def request(method, path, query, headers, body, extra \\ []) do
    headers =
      for {name, value} <- headers,
          name in @forward or (String.starts_with?(name, "x-kobo-") and name not in @not_forwarded),
          do: {name, value}

    req =
      Req.new(
        base_url: @base_url,
        method: method,
        url: path <> if(query in [nil, ""], do: "", else: "?" <> query),
        headers: headers ++ extra,
        body: body,
        decode_body: false,
        retry: false,
        receive_timeout: 20_000
      )
      |> Req.merge(Application.get_env(:stashix, :kobo_req_options, []))

    case Req.request(req) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        kobo_headers =
          for {name, values} <- resp_headers,
              String.starts_with?(name, "x-kobo-"),
              value <- List.wrap(values),
              do: {name, value}

        {:ok, %{status: status, headers: kobo_headers, body: resp_body, content_type: content_type(resp_headers)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_type(headers) do
    case headers["content-type"] do
      [type | _] -> type
      _ -> "application/json"
    end
  end

  @doc "Kobo's cover image of a book from its store."
  def cover_url(image_id, width, height),
    do: "https://cdn.kobo.com/book-images/#{image_id}/#{width}/#{height}/false/image.jpg"
end
