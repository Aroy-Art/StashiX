# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Library.ReaderKindTest do
  use ExUnit.Case, async: true

  alias Stashix.Library
  alias Stashix.Library.{Book, BookFile}

  test "the book's override wins over the detected kind" do
    assert Library.reader_kind(%Book{content_kind: :images}, %BookFile{content_kind: :text}) == :images
    assert Library.reader_kind(%Book{content_kind: :text}, %BookFile{content_kind: :images}) == :text
  end

  test "without an override the detected kind decides" do
    assert Library.reader_kind(%Book{}, %BookFile{content_kind: :text}) == :text
  end

  test "unknown reads as images" do
    assert Library.reader_kind(%Book{}, %BookFile{}) == :images
    assert Library.reader_kind(%Book{}, nil) == :images
  end
end
