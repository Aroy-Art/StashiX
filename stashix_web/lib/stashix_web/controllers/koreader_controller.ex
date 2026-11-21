# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.KoreaderController do
  @moduledoc """
  A KOReader progress sync server (the kosync protocol) under `/koreader`:
  in KOReader, Progress sync > Custom sync server is
  `https://<stashix>/koreader`, signed in with the user name and an app
  password (`StashixWeb.Plugs.KoreaderAuth`).

  Books are found by KOReader's document hash (`Stashix.Koreader`), so a
  book downloaded from the OPDS catalog syncs as it is. Progress lands in
  the same place as the web readers' and the OPDS apps'.
  """
  use StashixWeb, :controller

  alias Stashix.{Koreader, Library}

  @doc "Accounts are made in Stashix, not from KOReader."
  def create_user(conn, _params) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: 2005, message: "Make an app password in Stashix (Settings > Security) and log in with it."})
  end

  def auth(conn, _params), do: json(conn, %{authorized: "OK"})

  def show(conn, %{"document" => document}) do
    %{access: access, current_user: user} = conn.assigns

    with {:ok, book, file} <- Koreader.find(access, document),
         %{} = progress <- Library.get_progress(user.id, book.id) do
      locator = progress.locator || %{}

      json(conn, %{
        document: document,
        percentage: progress.progression,
        progress: progress_string(book, file, progress),
        device: locator["device"] || "Stashix",
        device_id: locator["device_id"] || "stashix",
        timestamp: progress.updated_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
      })
    else
      # KOReader reads an empty object as "nothing saved".
      nil -> json(conn, %{})
      {:error, :not_found} -> json(conn, %{})
      {:error, :ambiguous} -> conn |> put_status(:conflict) |> json(%{message: "More than one book has this file"})
    end
  end

  def update(conn, %{"document" => document, "progress" => position, "percentage" => percentage} = params)
      when is_binary(position) and is_number(percentage) do
    %{access: access, current_user: user} = conn.assigns
    device = %{"device" => string(params["device"]), "device_id" => string(params["device_id"])}

    with {:ok, book, file} <- Koreader.find(access, document),
         {:ok, page, opts} <- to_progress(book, file, position, percentage, device, user),
         {:ok, saved} <- Library.update_progress(access, user.id, book.id, page, opts) do
      json(conn, %{
        document: document,
        timestamp: saved.updated_at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
      })
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "No such book in Stashix"})
      {:error, :ambiguous} -> conn |> put_status(:conflict) |> json(%{message: "More than one book has this file"})
      _ -> conn |> put_status(:bad_request) |> json(%{message: "Invalid progress"})
    end
  end

  def update(conn, _params), do: conn |> put_status(:bad_request) |> json(%{message: "Invalid progress"})

  # Page books: the page from 1. Reflowable ones: KOReader's own XPointer
  # when it saved last, else the start of the chapter Stashix knows.
  defp progress_string(book, file, progress) do
    case mode(book, file) do
      :pages ->
        to_string((progress.current_page || 0) + 1)

      :reflow ->
        (progress.locator || %{})["koreader"] || Koreader.chapter_xpointer(file, (progress.locator || %{})["href"])
    end
  end

  defp to_progress(book, file, position, percentage, device, user) do
    percentage = percentage |> max(0) |> min(1) |> Kernel.*(1.0)

    case mode(book, file) do
      :pages ->
        case Integer.parse(position) do
          {n, ""} when n >= 1 and n <= max(book.page_count, 1) ->
            type = if file.format == :pdf and Library.reader_kind(book, file) == :text, do: "pdf", else: "image"
            {:ok, n - 1, locator: Map.merge(device, %{"type" => type, "page" => n - 1})}

          _ ->
            :error
        end

      :reflow ->
        href = Koreader.spine_href(file, Koreader.fragment_index(position))
        locator = %{"type" => locator_type(file.format), "koreader" => String.slice(position, 0, 1024), "href" => href}
        saved = Library.get_progress(user.id, book.id)
        page = (saved && saved.current_page) || 0
        {:ok, page, progression: percentage, locator: Map.merge(device, locator) |> reject_nil()}
    end
  end

  defp mode(book, file) do
    if Library.reader_kind(book, file) == :images or file.format == :pdf, do: :pages, else: :reflow
  end

  defp locator_type(format) do
    cond do
      Stashix.Media.Formats.mobi?(format) -> "mobi"
      Stashix.Media.Formats.fb2?(format) -> "fb2"
      true -> to_string(format)
    end
  end

  defp string(value) when is_binary(value), do: String.slice(value, 0, 200)
  defp string(_), do: nil

  defp reject_nil(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()
end
