# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Media.Formats do
  @moduledoc """
  The book file formats the library takes, by extension.

  Mostly one extension per format; a zipped FictionBook comes as `.fbz` or
  `.fb2.zip`, so the format is read off the name rather than
  `Path.extname/1` alone (a bare `.zip` is not a book).
  """

  @formats %{
    ".cbz" => :cbz,
    ".cbr" => :cbr,
    ".cb7" => :cb7,
    ".epub" => :epub,
    ".pdf" => :pdf,
    ".mobi" => :mobi,
    ".azw3" => :azw3,
    ".azw" => :azw,
    ".fb2" => :fb2,
    ".fbz" => :fbz,
    ".fb2.zip" => :fbz
  }

  @doc "Every format, as stored on `Stashix.Library.BookFile`."
  def all, do: [:cbz, :cbr, :cb7, :epub, :pdf, :mobi, :azw3, :azw, :fb2, :fbz]

  @doc "Every extension, lower case, with the dot (`.fb2.zip` included)."
  def extensions, do: Map.keys(@formats)

  @doc "The format of `path` by its name, or nil when it is not a book."
  @spec format(Path.t()) :: atom() | nil
  def format(path), do: @formats[extension(path)]

  @doc "Whether `path` is named like a book the library takes."
  def supported?(path), do: format(path) != nil

  @doc "The file's extension as `format/1` reads it: `.fb2.zip` stays whole."
  def extension(path) do
    path = String.downcase(path)
    if String.ends_with?(path, ".fb2.zip"), do: ".fb2.zip", else: Path.extname(path)
  end

  @doc ~S(The file name without its book extension: "Dune.fb2.zip" → "Dune".)
  def stem(path) do
    name = Path.basename(path)
    ext = if extension(name) == ".fb2.zip", do: 8, else: byte_size(Path.extname(name))
    binary_part(name, 0, byte_size(name) - ext)
  end

  @doc "Formats in the Kindle (Mobipocket / KF8) family."
  def mobi?(format), do: format in [:mobi, :azw3, :azw]

  @doc "FictionBook, plain or zipped."
  def fb2?(format), do: format in [:fb2, :fbz]
end
