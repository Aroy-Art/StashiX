# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.SidecarTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.Sidecar

  @moduletag :tmp_dir

  test "paths are named after the format" do
    assert Sidecar.path("/c/Batman 001.cbr", :metroninfo) == "/c/Batman 001.MetronInfo.xml"
    assert Sidecar.path("/c/Batman 001.cbr", :comicinfo) == "/c/Batman 001.ComicInfo.xml"
  end

  test "stem maps every sidecar name back to its book" do
    for ext <- ~w(.MetronInfo.xml .ComicInfo.xml .xml .jpg) do
      assert Sidecar.stem("/c/Batman 001" <> ext) == "/c/Batman 001"
    end

    assert Sidecar.stem("/c/Vol. 2.xml") == "/c/Vol. 2"
  end

  test "a named sidecar beats an old <stem>.xml of the same format", %{tmp_dir: dir} do
    book = Path.join(dir, "Batman 001.cbr")
    File.write!(Path.join(dir, "Batman 001.xml"), "<ComicInfo><Title>old</Title></ComicInfo>")
    assert %{comicinfo: "<ComicInfo><Title>old" <> _} = Sidecar.read(book)

    File.write!(Sidecar.path(book, :comicinfo), "<ComicInfo><Title>new</Title></ComicInfo>")
    File.write!(Sidecar.path(book, :metroninfo), "<MetronInfo/>")
    assert %{comicinfo: "<ComicInfo><Title>new" <> _, metroninfo: "<MetronInfo/>"} = Sidecar.read(book)
  end

  test "an old <stem>.xml that isn't metadata is ignored", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "Batman 001.xml"), "<Something/>")
    assert Sidecar.legacy(Path.join(dir, "Batman 001.cbr")) == nil
    assert Sidecar.read(Path.join(dir, "Batman 001.cbr")) == %{}
  end
end
