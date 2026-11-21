# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Opds.Progression do
  @moduledoc """
  Reading progress as the Readium Progression API carries it (the OPDS 2
  progression proposal, as Komga and Readium apps use it):

      %{"modified" => "2026-11-21T10:00:00Z",
        "device" => %{"id" => "...", "name" => "..."},
        "locator" => %{"href" => "...", "type" => "...",
                       "locations" => %{"position" => 12, "progression" => 0.4,
                                        "totalProgression" => 0.4}}}

  `position` counts pages from 1. How a locator maps onto Stashix progress
  (`Stashix.Library.ReadingProgress`) depends on how the book reads:

    * page images (comics, scanned PDFs) and text PDFs go by page; the
      href of an image page is its entry in the Divina manifest
    * EPUB and other reflowable books go by `totalProgression`, with the
      chapter href kept. Stashix's own reader places itself by CFI, which
      apps don't send, so there it reopens where it was last read in
      Stashix; progress bars and Continue reading follow the app.
  """

  alias Stashix.Library
  alias Stashix.Library.ReadingProgress

  @base StashixWeb.Opds.Feed2.base()

  @doc "How the book reads: `:images`, `:pdf` (text PDF) or `:reflow`."
  def mode(book) do
    case Library.get_preferred_book_file(book) do
      nil -> :images
      file -> mode(book, file)
    end
  end

  defp mode(book, file) do
    cond do
      Library.reader_kind(book, file) == :images -> :images
      file.format == :pdf -> :pdf
      true -> :reflow
    end
  end

  @doc "The progression document for saved progress."
  def to_json(%ReadingProgress{} = progress, book) do
    page = progress.current_page || 0

    {href, type, locations} =
      case mode(book) do
        :images ->
          {"#{@base}/books/#{book.id}/page/#{page}", "image/jpeg", %{position: page + 1}}

        :pdf ->
          {"#{@base}/books/#{book.id}/download?formats=pdf", "application/pdf", %{position: page + 1}}

        :reflow ->
          {(progress.locator || %{})["href"] || "", "application/xhtml+xml", %{}}
      end

    %{
      modified: StashixWeb.Opds.timestamp(progress.updated_at),
      device: %{id: "urn:stashix:server", name: "Stashix"},
      locator: %{
        href: href,
        type: type,
        locations: Map.merge(locations, %{progression: progress.progression, totalProgression: progress.progression})
      }
    }
  end

  @doc """
  The page and `Stashix.Library.update_progress/5` options for a
  progression document, or `{:error, reason}`.
  """
  def from_json(%{"locator" => %{} = locator} = doc, book, saved) do
    locations = locator["locations"] || %{}
    at = modified(doc["modified"])

    case mode(book) do
      mode when mode in [:images, :pdf] ->
        with {:ok, page} <- page(locations, locator["href"], book) do
          {:ok, page, [locator: %{"type" => if(mode == :pdf, do: "pdf", else: "image"), "page" => page}, at: at]}
        end

      :reflow ->
        case number(locations["totalProgression"]) || number(locations["progression"]) do
          nil ->
            {:error, "locations.totalProgression is required"}

          progression ->
            href = if is_binary(locator["href"]), do: String.slice(locator["href"], 0, 1024)
            type = (saved && saved.locator && saved.locator["type"]) || "epub"
            locator = if href, do: %{"type" => type, "href" => href}, else: nil
            {:ok, (saved && saved.current_page) || 0, [progression: progression, locator: locator, at: at]}
        end
    end
  end

  def from_json(_doc, _book, _saved), do: {:error, "locator is required"}

  # The page index from a 1-based position, the manifest href, or how far through.
  defp page(locations, href, book) do
    count = max(book.page_count, 1)

    page =
      cond do
        is_integer(locations["position"]) ->
          locations["position"] - 1

        is_binary(href) and Regex.match?(~r"/page/\d+$", href) ->
          href |> String.split("/") |> List.last() |> String.to_integer()

        progression = number(locations["totalProgression"]) ->
          round(progression * (count - 1))

        true ->
          nil
      end

    if is_integer(page) and page in 0..(count - 1)//1,
      do: {:ok, page},
      else: {:error, "position must be within 1 and the page count (#{count})"}
  end

  @doc "Whether a document's `modified` is older than what is saved (a 409)."
  def stale?(%{"modified" => modified}, %ReadingProgress{updated_at: saved}) do
    case modified(modified) do
      nil -> false
      at -> NaiveDateTime.compare(at, saved) == :lt
    end
  end

  def stale?(_doc, _saved), do: false

  defp modified(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      _ -> nil
    end
  end

  defp modified(_), do: nil

  defp number(n) when is_number(n) and n >= 0 and n <= 1, do: n * 1.0
  defp number(_), do: nil
end
