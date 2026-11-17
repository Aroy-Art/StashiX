# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.ContentKind do
  @moduledoc """
  Whether a book file reads as page images (comics, scans) or as text, so it
  opens in the matching reader (see `Stashix.Library.reader_kind/2`).

  Comic archives are always images. A PDF is sampled with `pdftotext` over its
  first `@sample_pages` pages: plenty of text per page means a text PDF, next
  to none means scans. In between (an OCR'd comic with lettering picked up, a
  picture book) is `nil`, unknown, which reads as images.

  An EPUB is images when it is fixed layout or each spine document only
  wraps a picture (see `Stashix.Media.Epub.content_kind/1`), else text.
  """

  alias Stashix.Media.Epub

  @sample_pages 6
  # Average non-space characters per sampled page.
  @text_min 400
  @images_max 40

  @spec detect(Path.t()) :: :images | :text | nil
  def detect(path) do
    case path |> Path.extname() |> String.downcase() do
      ext when ext in ~w(.cbz .cbr .cb7) -> :images
      ".pdf" -> detect_pdf(path)
      ".epub" -> Epub.content_kind(path)
      _ -> nil
    end
  end

  defp detect_pdf(path) do
    case System.cmd("pdftotext", ["-q", "-f", "1", "-l", to_string(@sample_pages), "--", path, "-"]) do
      {out, 0} -> classify(out)
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  # pdftotext ends every page with a form feed.
  defp classify(text) do
    pages = text |> String.split("\f") |> Enum.drop(-1)

    if pages == [] do
      nil
    else
      chars = Enum.sum_by(pages, &(&1 |> String.replace(~r/\s+/u, "") |> String.length()))

      case chars / length(pages) do
        avg when avg >= @text_min -> :text
        avg when avg <= @images_max -> :images
        _ -> nil
      end
    end
  end
end
