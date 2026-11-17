# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.PdfFixtures do
  @moduledoc "Minimal PDFs built in memory, for tests that need poppler to read one."

  @doc """
  Writes a PDF to `path`, one page per entry: `{width, height}` in points
  for a blank page, or `{width, height, text}` for a page with lines of
  Helvetica text.
  """
  def make_pdf(path, pages) do
    n = length(pages)
    # 1 catalog, 2 pages, 3 font, then a page object and a content stream per page.
    page_ids = for i <- 0..(n - 1)//1, do: 4 + 2 * i
    kids = Enum.map_join(page_ids, " ", &"#{&1} 0 R")

    page_objs =
      Enum.flat_map(Enum.zip(pages, page_ids), fn {page, id} ->
        {w, h, text} = with {w, h} <- page, do: {w, h, ""}
        stream = content_stream(text, h)

        [
          "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{w} #{h}] " <>
            "/Resources << /Font << /F1 3 0 R >> >> /Contents #{id + 1} 0 R >>",
          "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream"
        ]
      end)

    objs =
      [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [#{kids}] /Count #{n} >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      ] ++ page_objs

    {body, offsets} =
      objs
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {obj, i}, {acc, offs} ->
        {acc <> "#{i} 0 obj\n#{obj}\nendobj\n", [byte_size(acc) | offs]}
      end)

    size = length(objs) + 1

    xref =
      "xref\n0 #{size}\n0000000000 65535 f \n" <>
        Enum.map_join(Enum.reverse(offsets), &(String.pad_leading("#{&1}", 10, "0") <> " 00000 n \n"))

    trailer = "trailer\n<< /Size #{size} /Root 1 0 R >>\nstartxref\n#{byte_size(body)}\n%%EOF\n"
    File.write!(path, body <> xref <> trailer)
    path
  end

  defp content_stream("", _h), do: ""

  defp content_stream(text, h) do
    lines =
      text
      |> String.split("\n")
      |> Enum.map_join(" T* ", &"(#{String.replace(&1, ~r/([()\\\\])/, "\\\\\\1")}) Tj")

    "BT /F1 10 Tf 12 TL 20 #{h - 30} Td #{lines} ET"
  end
end
