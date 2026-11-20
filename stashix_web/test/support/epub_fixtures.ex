# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.EpubFixtures do
  @moduledoc "Minimal EPUBs built in memory."

  @doc """
  Writes an EPUB with its package at `OEBPS/content.opf`. `chapters` is a
  list of `{:text, body_text}` or `{:image, image_name}` spine documents, in
  reading order. Options: `layout:` (e.g. "pre-paginated"), `extra:` more
  `{name, data}` entries, `title:` (default "Test"), `metadata:` more XML
  inside `<metadata>`.
  """
  def make_epub(path, chapters, opts \\ []) do
    docs =
      chapters
      |> Enum.with_index(1)
      |> Enum.map(fn
        {{:text, text}, i} -> {"ch#{i}", "text/ch#{i}.xhtml", xhtml("<p>#{text}</p>")}
        {{:image, img}, i} -> {"ch#{i}", "text/ch#{i}.xhtml", xhtml(~s(<img src="../images/#{img}" alt=""/>))}
      end)

    images = for {:image, img} <- chapters, uniq: true, do: img

    manifest =
      Enum.map_join(docs, "\n", fn {id, href, _} ->
        ~s(<item id="#{id}" href="#{href}" media-type="application/xhtml+xml"/>)
      end) <>
        Enum.map_join(images, "\n", &~s(<item id="img-#{&1}" href="images/#{&1}" media-type="image/jpeg"/>))

    spine = Enum.map_join(docs, "\n", fn {id, _, _} -> ~s(<itemref idref="#{id}"/>) end)

    layout =
      if opts[:layout], do: ~s(<meta property="rendition:layout">#{opts[:layout]}</meta>), else: ""

    opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="id">test</dc:identifier><dc:title>#{opts[:title] || "Test"}</dc:title>#{layout}#{opts[:metadata]}
      </metadata>
      <manifest>#{manifest}</manifest>
      <spine>#{spine}</spine>
    </package>
    """

    container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """

    entries =
      [{~c"mimetype", "application/epub+zip"}, {~c"META-INF/container.xml", container}, {~c"OEBPS/content.opf", opf}] ++
        for({_, href, body} <- docs, do: {String.to_charlist("OEBPS/" <> href), body}) ++
        for(img <- images, do: {String.to_charlist("OEBPS/images/" <> img), "jpeg:" <> img}) ++
        for({name, data} <- opts[:extra] || [], do: {String.to_charlist(name), data})

    {:ok, _} = :zip.create(String.to_charlist(path), entries)
    path
  end

  defp xhtml(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head><body>#{body}</body></html>
    """
  end
end
