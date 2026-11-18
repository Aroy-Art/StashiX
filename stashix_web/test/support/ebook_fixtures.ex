# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.EbookFixtures do
  @moduledoc "Minimal Kindle (MOBI) and FictionBook files built in memory."

  @doc """
  Writes a Palm database MOBI: record 0 (PalmDOC, MOBI and EXTH headers), one
  uncompressed text record and, with `cover:`, a picture record. Options:
  `title:`, `text:`, `exth:` a list of `{type, binary}`, `cover:` image
  bytes, `encryption:` (non-zero for DRM).
  """
  def make_mobi(path, opts \\ []) do
    text = Keyword.get(opts, :text, "<html><body><p>Call me Ishmael.</p></body></html>")
    title = Keyword.get(opts, :title, "Test Book")
    cover = opts[:cover]

    exth_records =
      Keyword.get(opts, :exth, []) ++ if(cover, do: [{201, <<0::32>>}], else: [])

    exth_body = for {type, data} <- exth_records, into: <<>>, do: <<type::32, byte_size(data) + 8::32, data::binary>>
    exth = <<"EXTH", byte_size(exth_body) + 12::32, length(exth_records)::32, exth_body::binary>>

    header_length = 232
    name_offset = 16 + header_length + byte_size(exth)

    mobi =
      <<"MOBI", header_length::32, 2::32, 65_001::32, 1::32, 6::32>> <>
        :binary.copy(<<0xFF>>, 40) <>
        <<0::32, name_offset::32, byte_size(title)::32, 9::32, 0::32, 0::32, 2::32>> <>
        <<0::32, 0::32, 0::32, 0::32, 0::32, 0x40::32>>

    # Field offsets in record 0: full name at 84/88, first image at 108,
    # EXTH flags at 128.
    mobi = put_u32(mobi, 108 - 16, 2)
    mobi = mobi <> :binary.copy(<<0>>, header_length - byte_size(mobi))

    palmdoc = <<1::16, 0::16, byte_size(text)::32, 1::16, 4096::16, Keyword.get(opts, :encryption, 0)::16, 0::16>>
    record0 = palmdoc <> mobi <> exth <> title <> <<0, 0>>

    records = [record0, text] ++ if(cover, do: [cover], else: [])
    count = length(records)
    first = 78 + count * 8 + 2

    {table, _} =
      Enum.map_reduce(Enum.with_index(records), first, fn {rec, i}, at ->
        {<<at::32, 0::8, i::24>>, at + byte_size(rec)}
      end)

    name = String.pad_trailing(String.slice(title, 0, 31), 32, <<0>>)

    pdb =
      name <> :binary.copy(<<0>>, 28) <> "BOOK" <> "MOBI" <> :binary.copy(<<0>>, 8) <> <<count::16>>

    File.write!(path, [pdb, table, <<0, 0>>, records])
    path
  end

  defp put_u32(bin, at, value) do
    <<before::binary-size(^at), _::32, rest::binary>> = bin
    <<before::binary, value::32, rest::binary>>
  end

  @doc """
  Writes a FictionBook. Options: `title:`, `authors:` ({first, last}),
  `sequence:` ({name, number}), `annotation:`, `cover:` image bytes,
  `zip: true` for `.fbz` / `.fb2.zip` (path decides the name).
  """
  def make_fb2(path, opts \\ []) do
    authors =
      opts
      |> Keyword.get(:authors, [{"Jane", "Austen"}])
      |> Enum.map_join(fn {first, last} ->
        "<author><first-name>#{first}</first-name><last-name>#{last}</last-name></author>"
      end)

    sequence =
      case opts[:sequence] do
        {name, number} -> ~s(<sequence name="#{name}" number="#{number}"/>)
        nil -> ""
      end

    {coverpage, binary} =
      case opts[:cover] do
        nil ->
          {"", ""}

        bytes ->
          {~s(<coverpage><image l:href="#cover.jpg"/></coverpage>),
           ~s(<binary id="cover.jpg" content-type="image/jpeg">#{Base.encode64(bytes)}</binary>)}
      end

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
      <description>
        <title-info>
          <genre>prose_classic</genre>
          #{authors}
          <book-title>#{Keyword.get(opts, :title, "Persuasion")}</book-title>
          <annotation><p>#{Keyword.get(opts, :annotation, "A second chance.")}</p></annotation>
          <date value="1817-12-20">1817</date>
          #{coverpage}
          <lang>en</lang>
          #{sequence}
        </title-info>
        <publish-info><publisher>John Murray</publisher><isbn>978-0-14-143968-8</isbn></publish-info>
      </description>
      <body><section><title><p>Chapter 1</p></title><p>Sir Walter Elliot, of Kellynch Hall…</p></section></body>
      #{binary}
    </FictionBook>
    """

    if opts[:zip] do
      {:ok, _} = :zip.create(String.to_charlist(path), [{~c"book.fb2", xml}])
    else
      File.write!(path, xml)
    end

    path
  end
end
