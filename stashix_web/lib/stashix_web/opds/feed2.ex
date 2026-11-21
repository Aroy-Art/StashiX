# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Opds.Feed2 do
  @moduledoc """
  OPDS 2.0 (JSON) rendering of the feeds described in `StashixWeb.Opds`,
  under `/opds/v2`.

  Publications link their files (with download permission), a Divina
  manifest when they read as page images (`manifest/1`), and the Readium
  Progression API (`StashixWeb.Opds.Progression`) so apps can read and
  write where the user is.
  """

  import StashixWeb.Opds

  @base "/opds/v2"
  @feed_type "application/opds+json"
  @publication_type "application/opds-publication+json"
  @divina_type "application/divina+json"

  def base, do: @base

  def content_type(_kind), do: @feed_type
  def publication_type, do: @publication_type
  def divina_type, do: @divina_type

  @doc "A feed, rendered."
  def render(feed) do
    {navigation, books} = Enum.split_with(feed.entries, &match?({:nav, _}, &1))

    %{
      metadata: metadata(feed),
      links: links(feed),
      navigation: if(navigation != [], do: Enum.map(navigation, &navigation/1)),
      publications: if(books != [] or feed.kind == :acquisition, do: Enum.map(books, &publication/1))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    |> Jason.encode_to_iodata!()
  end

  defp metadata(%{page: %{page: page, per_page: per, total: total}} = feed),
    do: %{title: feed.title, numberOfItems: total, itemsPerPage: per, currentPage: page}

  defp metadata(feed), do: %{title: feed.title}

  defp links(feed) do
    [
      %{rel: "self", href: @base <> feed.self, type: @feed_type},
      %{rel: "start", href: @base <> "/catalog", type: @feed_type},
      feed[:up] && %{rel: "up", href: @base <> feed.up, type: @feed_type},
      %{rel: "search", href: @base <> "/search{?query}", type: @feed_type, templated: true}
      | page_links(feed)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp page_links(%{page: %{page: page} = paging, self: self}) do
    last = last_page(paging)
    path = @base <> self

    [
      page > 1 && %{rel: "first", href: page_path(path, 1), type: @feed_type},
      page > 1 && %{rel: "previous", href: page_path(path, page - 1), type: @feed_type},
      page < last && %{rel: "next", href: page_path(path, page + 1), type: @feed_type},
      page < last && %{rel: "last", href: page_path(path, last), type: @feed_type}
    ]
    |> Enum.filter(& &1)
  end

  defp page_links(_feed), do: []

  defp navigation({:nav, entry}) do
    compact(%{href: @base <> entry.href, title: entry.title, type: @feed_type, rel: "subsection", properties: nil})
  end

  @doc "One publication (a book) as a map."
  def publication({:book, book, opts}), do: publication(book, opts)

  def publication(book, opts) do
    cover = "#{@base}/books/#{book.id}/cover"

    %{
      metadata: book_metadata(book),
      links:
        [
          %{rel: "self", href: "#{@base}/books/#{book.id}", type: @publication_type},
          if(opts[:stream?] && book.page_count > 0,
            do: %{href: "#{@base}/books/#{book.id}/manifest", type: @divina_type}
          ),
          %{rel: progression_rel(), href: "#{@base}/books/#{book.id}/progression", type: progression_type()}
          | if(opts[:download?], do: Enum.map(files(book), &acquisition(book, &1)), else: [])
        ]
        |> Enum.reject(&is_nil/1),
      images: [
        %{href: cover, type: "image/jpeg"},
        %{href: cover <> "?s=s", type: "image/jpeg", rel: "http://opds-spec.org/image/thumbnail"}
      ]
    }
  end

  defp acquisition(book, file) do
    %{
      rel: "http://opds-spec.org/acquisition",
      href: "#{@base}/books/#{book.id}/download?formats=#{file.format}",
      type: mime(file.format),
      title: file.format |> to_string() |> String.upcase(),
      properties: %{size: file.file_size}
    }
  end

  defp book_metadata(book) do
    compact(%{
      "@type": "http://schema.org/Book",
      title: entry_title(book),
      identifier: identifier(book),
      modified: timestamp(book.updated_at),
      language: book.language,
      description: book.summary,
      published: book.year && to_string(book.year),
      numberOfPages: if(book.page_count > 0, do: book.page_count),
      author: Enum.map(authors(book), &%{name: &1}),
      belongsTo: series(book)
    })
  end

  defp identifier(%{calibre_uuid: uuid} = book) when is_binary(uuid), do: entry_id(book)
  defp identifier(%{isbn: isbn}) when is_binary(isbn), do: "urn:isbn:" <> isbn
  defp identifier(book), do: "urn:uuid:#{book.id}"

  defp series(%{series: %{name: name}} = book) when is_binary(name) do
    position = book.issue_number && book.issue_number |> Decimal.to_float()
    %{series: [compact(%{name: name, position: position})]}
  end

  defp series(_book), do: nil

  @doc """
  A Divina manifest: the book's pages in reading order, each from the page
  endpoint (which counts from 0). Readium apps stream comics from it.
  """
  def manifest(book) do
    %{
      "@context": "https://readium.org/webpub-manifest/context.jsonld",
      metadata: Map.put(book_metadata(book), :conformsTo, "https://readium.org/webpub-manifest/profiles/divina"),
      links: [
        %{rel: "self", href: "#{@base}/books/#{book.id}/manifest", type: @divina_type},
        %{rel: progression_rel(), href: "#{@base}/books/#{book.id}/progression", type: progression_type()}
      ],
      readingOrder:
        for(n <- 0..(book.page_count - 1)//1, do: %{href: "#{@base}/books/#{book.id}/page/#{n}", type: "image/jpeg"}),
      resources: [%{href: "#{@base}/books/#{book.id}/cover", type: "image/jpeg", rel: "cover"}]
    }
  end

  @doc "The OPDS authentication document: HTTP Basic with an app password."
  def authentication_document do
    %{
      id: @base <> "/auth",
      title: "Stashix",
      description: "Sign in with your user name and an app password from Settings > Security.",
      authentication: [
        %{type: "http://opds-spec.org/auth/basic", labels: %{login: "User name", password: "App password"}}
      ]
    }
  end

  defp compact(map), do: map |> Enum.reject(fn {_k, v} -> v in [nil, []] end) |> Map.new()
end
