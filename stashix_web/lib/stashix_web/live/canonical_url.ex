# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Live.CanonicalUrl do
  @moduledoc """
  Keeps detail pages on their canonical slug URL.

  When the `"id"` param isn't the record's current `Phoenix.Param` (a full
  UUID link, a bare short id, or a slug from before a rename), the page is
  patched to the canonical URL, keeping the rest of the path and the query
  string. On the first, disconnected render that patch becomes an HTTP
  redirect.
  """

  import Phoenix.LiveView

  @doc "Attaches the hook; `key` names the assign holding the page's record."
  def attach(socket, key) do
    attach_hook(socket, :canonical_url, :handle_params, fn params, uri, socket ->
      case canonical_path(params["id"], uri, socket.assigns[key]) do
        nil -> {:cont, socket}
        path -> {:halt, push_patch(socket, to: path, replace: true)}
      end
    end)
  end

  @doc """
  The canonical path for `uri`, or nil when `param` already is canonical (or
  can't be found in the path).
  """
  def canonical_path(param, uri, record) when is_binary(param) and not is_nil(record) do
    canonical = Phoenix.Param.to_param(record)
    if param != canonical, do: replace_segment(uri, param, canonical)
  end

  def canonical_path(_param, _uri, _record), do: nil

  defp replace_segment(uri, param, canonical) do
    %URI{path: path, query: query} = URI.parse(uri)
    segments = String.split(path, "/")

    case Enum.find_index(segments, &(URI.decode(&1) == param)) do
      nil ->
        nil

      i ->
        path = segments |> List.replace_at(i, URI.encode(canonical)) |> Enum.join("/")
        if query, do: path <> "?" <> query, else: path
    end
  end
end
