# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.SeriesLive do
  use StashixWeb, :live_view

  alias Stashix.{Formatters, Library, Metadata, Scanner, Slug}
  alias StashixWeb.Live.CanonicalUrl
  alias Stashix.Accounts.User
  alias Stashix.Media.ImageResizer
  alias Stashix.Metadata.Roles
  import StashixWeb.MetadataComponents
  import StashixWeb.DetailComponents
  import StashixWeb.DialogHistory

  on_mount({StashixWeb.Live.Hooks, :require_auth})

  @admin_events ~w(fetch_metadata toggle_metadata_lock rescan_series force_rescan_series open_push_publishers_dialog close_push_publishers_dialog push_publishers_to_issues set_push_publishers_mode toggle_push_preview open_push_age_rating_dialog close_push_age_rating_dialog set_push_age_rating_target set_push_age_rating_mode toggle_push_age_rating_preview push_age_rating_to_issues open_push_language_dialog close_push_language_dialog set_push_language set_push_language_mode push_language_to_issues open_issue_numbers_dialog close_issue_numbers_dialog toggle_issue_number apply_issue_numbers)

  @age_ratings Ecto.Enum.values(Stashix.Library.Book, :age_rating)

  @impl true
  def mount(%{"id" => param}, _session, socket) do
    id = Slug.resolve!(Stashix.Library.Series, param)
    series = Library.get_series_with_books(socket.assigns.access, id)
    library = Library.get_readable_library!(socket.assigns.access, series.library_id)

    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Library.total_size_for_series(socket.assigns.access, series.id)
    sort = "issue_asc"
    books = sort_books(series.books, sort)
    cover_book = List.first(books)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)
    continue_book = find_continue_book(books, progress_map)
    summary_info = derive_summary(series, books)
    folder_cover = Library.series_folder_cover(socket.assigns.access, series)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Stashix.PubSub, "scan:#{library.id}")
      Metadata.subscribe(library.id)
    end

    socket = CanonicalUrl.attach(socket, :series)

    {:ok,
     socket
     |> track_dialogs(~w(edit identify))
     |> assign(
       page_title: series.name,
       series: series,
       library: library,
       books: books,
       sort: sort,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: cover_book,
       folder_cover?: folder_cover != nil,
       folder_cover_blurhash: folder_cover && ImageResizer.blurhash(folder_cover),
       continue_book: continue_book,
       summary_info: summary_info,
       scanning: false,
       show_admin_menu: false,
       sources_ready: socket.assigns.current_user.role == :admin && Stashix.Metadata.Sources.any_ready?(),
       show_edit_dialog: false,
       show_identify_dialog: false,
       show_push_publishers_dialog: false,
       push_publisher_ids: [],
       push_publishers_mode: :replace,
       push_publishers_preview: nil,
       show_push_preview: false,
       show_push_age_rating_dialog: false,
       push_age_rating_target: nil,
       push_age_rating_mode: :replace,
       push_age_rating_preview: nil,
       show_push_age_rating_preview: false,
       push_language: nil,
       push_language_mode: :replace,
       push_language_preview: nil,
       issue_numbers_preview: nil,
       issue_numbers_skipped: MapSet.new(),
       series_details: Library.series_details(socket.assigns.access, series.id),
       all_publishers: Library.list_all_publishers(),
       book_publishers: Library.series_book_publishers(series.id),
       age_ratings: @age_ratings
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, show_edit_dialog: params["edit"] == "true" && socket.assigns.current_user.role == :admin)

    socket =
      assign(socket,
        show_identify_dialog: params["identify"] == "true" && socket.assigns.current_user.role == :admin
      )

    {:noreply, socket}
  end

  # Age rating lives on books; the series-level setting overwrites every issue.
  defp assign_push_language(socket, language, mode) do
    preview = Library.push_language_preview(socket.assigns.series.id, language, mode)
    assign(socket, push_language: language, push_language_mode: mode, push_language_preview: preview)
  end

  defp blank_language(nil), do: nil
  defp blank_language(s), do: if(String.trim(s) == "", do: nil, else: String.trim(s))

  # The shared age rating of all issues, or nil when mixed/empty.
  defp common_age_rating(books) do
    case books |> Enum.map(& &1.age_rating) |> Enum.uniq() do
      [rating] -> rating
      _ -> nil
    end
  end

  defp year_range(%{start_year: nil}), do: nil
  defp year_range(%{start_year: s, end_year: nil, ongoing: true}), do: "#{s}–"
  defp year_range(%{start_year: s, end_year: nil}), do: "#{s}"
  defp year_range(%{start_year: s, end_year: e}), do: "#{s}–#{e}"

  # Series-level facts for the details grid; empty values are dropped by the grid.
  defp series_facts(series) do
    [
      {gettext("Format"), series.format && to_string(series.format)},
      {gettext("Also known as"), Enum.map_join(series.alternative_names, " · ", & &1.name)},
      {gettext("Published issues"), series.issue_count > 0 && series.issue_count},
      {gettext("Volumes"), series.volume_count > 0 && series.volume_count},
      {gettext("Metadata source"), metadata_source_label(series)},
      {gettext("External IDs"), Enum.map_join(series.external_ids, " · ", &"#{&1.source} #{&1.source_id}")}
    ]
    |> Enum.map(fn {label, value} -> {label, value || nil} end)
  end

  defp metadata_source_label(%{metadata_matched_at: nil}), do: nil

  defp metadata_source_label(series) do
    mod = Stashix.Metadata.Sources.module(series.metadata_source || "")
    name = (mod && mod.name()) || series.metadata_source

    assigns = %{name: name, matched_at: series.metadata_matched_at}

    ~H"""
    <span :if={@name}>{@name} ·</span>
    <.local_time id="series-metadata-matched" value={@matched_at} />
    """
  end

  defp relative_folder(series, library) do
    library.name <>
      "/" <>
      (String.replace_prefix(series.path || "", library.root_path, "")
       |> String.trim_leading("/"))
  end

  @impl true
  # Metadata editing and rescans are admin-only; the UI hides them for other
  # users, and this drops the events if sent anyway.
  def handle_event(event, _params, %{assigns: %{current_user: %{role: role}}} = socket)
      when event in @admin_events and role != :admin do
    {:noreply, socket}
  end

  def handle_event("sort", %{"value" => sort}, socket) do
    {:noreply, assign(socket, sort: sort, books: sort_books(socket.assigns.series.books, sort))}
  end

  def handle_event("toggle_admin_menu", _, socket) do
    {:noreply, assign(socket, show_admin_menu: !socket.assigns.show_admin_menu)}
  end

  def handle_event("open_edit_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series}?edit=true")}
  end

  def handle_event("close_edit_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/series/#{socket.assigns.series}")}
  end

  def handle_event("fetch_metadata", _params, socket) do
    case Metadata.enqueue_series(socket.assigns.series.id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, gettext("Looking up metadata for the series and its issues…"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not queue metadata lookup"))}
    end
  end

  def handle_event("open_identify_dialog", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/series/#{socket.assigns.series}?identify=true")}
  end

  def handle_event("close_identify_dialog", _params, socket) do
    {:noreply, close_dialog(socket, ~p"/series/#{socket.assigns.series}")}
  end

  def handle_event("toggle_metadata_lock", _params, socket) do
    series = socket.assigns.series
    {:ok, _} = Metadata.set_locked(series, !series.metadata_locked)
    {:noreply, reload_series(socket)}
  end

  def handle_event("open_push_publishers_dialog", params, socket) do
    series = socket.assigns.series
    # Use IDs from the form's current state (may be unsaved); fall back to saved publishers.
    ids =
      case params["publisher_ids"] do
        [_ | _] = list -> Enum.reject(list, &(&1 == ""))
        _ -> Enum.map(series.publishers, & &1.id)
      end

    preview = Library.push_publishers_preview(series.id, ids, :replace)

    {:noreply,
     assign(socket,
       show_push_publishers_dialog: true,
       push_publisher_ids: ids,
       push_publishers_mode: :replace,
       push_publishers_preview: preview,
       show_push_preview: false
     )}
  end

  def handle_event("close_push_publishers_dialog", _params, socket) do
    {:noreply, assign(socket, show_push_publishers_dialog: false)}
  end

  def handle_event("set_push_publishers_mode", %{"mode" => mode}, socket) do
    atom = String.to_existing_atom(mode)
    preview = Library.push_publishers_preview(socket.assigns.series.id, socket.assigns.push_publisher_ids, atom)
    {:noreply, assign(socket, push_publishers_mode: atom, push_publishers_preview: preview)}
  end

  def handle_event("toggle_push_preview", _params, socket) do
    {:noreply, assign(socket, show_push_preview: !socket.assigns.show_push_preview)}
  end

  def handle_event("push_publishers_to_issues", _params, socket) do
    series = socket.assigns.series
    mode = socket.assigns.push_publishers_mode

    case Library.push_publishers_to_books(series.id, socket.assigns.push_publisher_ids, mode) do
      {:ok, []} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("No issues were updated."))
         |> assign(show_push_publishers_dialog: false)}

      {:ok, ids} ->
        if Stashix.Settings.metadata()["write_to_files"],
          do: Enum.each(ids, &Metadata.enqueue_write/1)

        series = Library.get_series_with_books(socket.assigns.access, series.id)
        books = sort_books(series.books, socket.assigns.sort)

        {:noreply,
         socket
         |> put_flash(
           :info,
           ngettext("Publishers pushed to 1 issue.", "Publishers pushed to %{count} issues.", length(ids))
         )
         |> assign(
           series: series,
           books: books,
           book_publishers: Library.series_book_publishers(series.id),
           show_push_publishers_dialog: false
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update publishers."))}
    end
  end

  def handle_event("open_push_age_rating_dialog", _params, socket) do
    series = socket.assigns.series
    default = common_age_rating(series.books) || :unknown
    target = Atom.to_string(default)
    preview = Library.push_age_rating_preview(series.id, target, :replace)

    {:noreply,
     assign(socket,
       show_push_age_rating_dialog: true,
       push_age_rating_target: target,
       push_age_rating_mode: :replace,
       push_age_rating_preview: preview,
       show_push_age_rating_preview: false
     )}
  end

  def handle_event("close_push_age_rating_dialog", _params, socket) do
    {:noreply, assign(socket, show_push_age_rating_dialog: false)}
  end

  def handle_event("set_push_age_rating_target", %{"rating" => rating}, socket) do
    preview = Library.push_age_rating_preview(socket.assigns.series.id, rating, socket.assigns.push_age_rating_mode)
    {:noreply, assign(socket, push_age_rating_target: rating, push_age_rating_preview: preview)}
  end

  def handle_event("set_push_age_rating_mode", %{"mode" => mode}, socket) do
    atom = String.to_existing_atom(mode)
    preview = Library.push_age_rating_preview(socket.assigns.series.id, socket.assigns.push_age_rating_target, atom)
    {:noreply, assign(socket, push_age_rating_mode: atom, push_age_rating_preview: preview)}
  end

  def handle_event("toggle_push_age_rating_preview", _params, socket) do
    {:noreply, assign(socket, show_push_age_rating_preview: !socket.assigns.show_push_age_rating_preview)}
  end

  def handle_event("push_age_rating_to_issues", _params, socket) do
    series = socket.assigns.series
    target = socket.assigns.push_age_rating_target
    only_unknown = socket.assigns.push_age_rating_mode == :fill

    case Library.set_series_age_rating(series.id, target, only_unknown: only_unknown) do
      {:ok, []} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("No issues were updated."))
         |> assign(show_push_age_rating_dialog: false)}

      {:ok, ids} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           ngettext("Age rating pushed to 1 issue.", "Age rating pushed to %{count} issues.", length(ids))
         )
         |> reload_series()
         |> assign(show_push_age_rating_dialog: false)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update age rating."))}
    end
  end

  # The edit dialog sends its (possibly unsaved) language; the menu uses the saved one.
  def handle_event("open_push_language_dialog", params, socket) do
    language = blank_language(params["language"]) || socket.assigns.series.language || "en"
    {:noreply, assign_push_language(socket, language, :replace)}
  end

  def handle_event("close_push_language_dialog", _params, socket) do
    {:noreply, assign(socket, push_language: nil, push_language_preview: nil)}
  end

  def handle_event("set_push_language", %{"language" => language}, socket) do
    language = blank_language(language) || socket.assigns.push_language
    {:noreply, assign_push_language(socket, language, socket.assigns.push_language_mode)}
  end

  def handle_event("set_push_language_mode", %{"mode" => mode}, socket) when mode in ~w(replace fill) do
    {:noreply, assign_push_language(socket, socket.assigns.push_language, String.to_existing_atom(mode))}
  end

  def handle_event("push_language_to_issues", _params, socket) do
    series = socket.assigns.series
    only_empty = socket.assigns.push_language_mode == :fill
    {:ok, ids} = Library.set_series_language(series.id, socket.assigns.push_language, only_empty: only_empty)

    if Stashix.Settings.metadata()["write_to_files"], do: Enum.each(ids, &Metadata.enqueue_write/1)

    message =
      case length(ids) do
        0 -> gettext("No issues were updated.")
        n -> ngettext("Language pushed to 1 issue.", "Language pushed to %{count} issues.", n)
      end

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> reload_series()
     |> assign(push_language: nil, push_language_preview: nil)}
  end

  def handle_event("open_issue_numbers_dialog", _params, socket) do
    preview = Library.filename_issue_numbers_preview(socket.assigns.series.id)
    {:noreply, assign(socket, issue_numbers_preview: preview, issue_numbers_skipped: MapSet.new())}
  end

  def handle_event("close_issue_numbers_dialog", _params, socket) do
    {:noreply, assign(socket, issue_numbers_preview: nil)}
  end

  def handle_event("toggle_issue_number", %{"id" => id}, socket) do
    skipped = socket.assigns.issue_numbers_skipped
    skipped = if MapSet.member?(skipped, id), do: MapSet.delete(skipped, id), else: MapSet.put(skipped, id)
    {:noreply, assign(socket, issue_numbers_skipped: skipped)}
  end

  def handle_event("apply_issue_numbers", _params, socket) do
    numbers =
      for entry <- socket.assigns.issue_numbers_preview.affected,
          not MapSet.member?(socket.assigns.issue_numbers_skipped, entry.book.id),
          into: %{},
          do: {entry.book.id, entry.to}

    case Library.set_issue_numbers(socket.assigns.series.id, numbers) do
      {:ok, ids} ->
        if Stashix.Settings.metadata()["write_to_files"], do: Enum.each(ids, &Metadata.enqueue_write/1)

        message =
          case length(ids) do
            0 -> gettext("No issues were updated.")
            n -> ngettext("Issue number updated on 1 issue.", "Issue numbers updated on %{count} issues.", n)
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> reload_series()
         |> assign(issue_numbers_preview: nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update issue numbers."))}
    end
  end

  def handle_event("rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  def handle_event("force_rescan_series", _, socket) do
    Scanner.scan_series(socket.assigns.series.id, true)
    {:noreply, assign(socket, scanning: true, show_admin_menu: false)}
  end

  @impl true
  def handle_info({:scan_progress, %{done: true}}, socket) do
    series = Library.get_series_with_books(socket.assigns.access, socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)
    book_ids = Enum.map(series.books, & &1.id)
    progress_map = Library.progress_map(socket.assigns.current_user.id, book_ids)
    total_pages = Enum.sum(Enum.map(series.books, & &1.page_count))
    total_size = Library.total_size_for_series(socket.assigns.access, series.id)
    folder_cover = Library.series_folder_cover(socket.assigns.access, series)

    {:noreply,
     assign(socket,
       scanning: false,
       series: series,
       books: books,
       progress_map: progress_map,
       total_pages: total_pages,
       total_size: total_size,
       cover_book: List.first(books),
       folder_cover?: folder_cover != nil,
       folder_cover_blurhash: folder_cover && ImageResizer.blurhash(folder_cover),
       continue_book: find_continue_book(books, progress_map),
       summary_info: derive_summary(series, books)
     )}
  end

  def handle_info({:cover_updated, book_id}, socket) do
    if Enum.any?(socket.assigns.books, &(&1.id == book_id)),
      do: {:noreply, replace_book_cover(socket, book_id)},
      else: {:noreply, socket}
  end

  def handle_info({:scan_progress, _}, socket), do: {:noreply, socket}
  def handle_info({:book_added, _}, socket), do: {:noreply, socket}

  def handle_info({:metadata_updated, :series, id}, %{assigns: %{series: %{id: id}}} = socket),
    do: {:noreply, reload_series(socket)}

  def handle_info({:metadata_updated, :book, book_id}, socket) do
    if Enum.any?(socket.assigns.books, &(&1.id == book_id)),
      do: {:noreply, reload_series(socket)},
      else: {:noreply, socket}
  end

  def handle_info({:metadata_updated, _, _}, socket), do: {:noreply, socket}

  def handle_info({:series_edit_saved, _id}, socket) do
    series = Library.get_series_with_books(socket.assigns.access, socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)

    {:noreply,
     socket
     |> assign(series: series, books: books, page_title: series.name, summary_info: derive_summary(series, books))
     |> put_flash(:info, gettext("Series saved"))
     |> close_dialog(~p"/series/#{series}")}
  end

  def handle_info({:identify_applied, :series, _id}, socket) do
    {:noreply,
     socket
     |> reload_series()
     |> put_flash(:info, gettext("Series metadata applied"))
     |> close_dialog(~p"/series/#{socket.assigns.series}")}
  end

  defp replace_book_cover(socket, book_id) do
    updated = Library.get_book_with_series(socket.assigns.access, book_id)

    books =
      Enum.map(socket.assigns.books, fn b ->
        if b.id == book_id, do: updated, else: b
      end)

    cover_book =
      if socket.assigns.cover_book && socket.assigns.cover_book.id == book_id,
        do: updated,
        else: socket.assigns.cover_book

    assign(socket, books: books, cover_book: cover_book)
  end

  defp reload_series(socket) do
    series = Library.get_series_with_books(socket.assigns.access, socket.assigns.series.id)
    books = sort_books(series.books, socket.assigns.sort)

    assign(socket,
      series: series,
      books: books,
      page_title: series.name,
      summary_info: derive_summary(series, books),
      series_details: Library.series_details(socket.assigns.access, series.id),
      book_publishers: Library.series_book_publishers(series.id)
    )
  end

  defp find_continue_book(books, progress_map) do
    issue_sorted = Library.sort_reading_order(books)

    in_progress =
      Enum.find(issue_sorted, fn b ->
        prog = progress_map[b.id]
        prog && prog > 0 && b.page_count && prog < b.page_count - 1
      end)

    in_progress ||
      Enum.find(issue_sorted, fn b ->
        prog = progress_map[b.id]
        is_nil(prog) || prog == 0
      end)
  end

  defp derive_summary(%{summary: s}, _books) when is_binary(s) and s != "",
    do: %{text: s, source: nil}

  defp derive_summary(_series, books) do
    issue_sorted = Library.sort_reading_order(books)

    case Enum.find(issue_sorted, fn b -> b.summary && b.summary != "" end) do
      nil ->
        nil

      book ->
        %{
          text: book.summary,
          source: Formatters.book_number_label(book, Library.volume_counts(books))
        }
    end
  end

  # Fraction read (0.0–1.0), or nil when the book has never been opened.
  defp run_fill_style(book, progress_map) do
    prog = book_progress(book, progress_map) || 0.0
    width = "width: #{round(prog * 100)}%;"

    bg =
      cond do
        prog >= 1.0 ->
          "background: #7c3aed;"

        prog > 0.0 ->
          "background: repeating-linear-gradient(-45deg, #7c3aed 0, #7c3aed 6px, light-dark(#ddd6fe, #1e1b4b) 6px, light-dark(#ddd6fe, #1e1b4b) 12px);"

        true ->
          ""
      end

    width <> bg
  end

  defp book_progress(book, progress_map) do
    prog = progress_map[book.id]

    if prog && book.page_count && book.page_count > 1,
      do: min(prog / (book.page_count - 1), 1.0),
      else: nil
  end

  defp run_segment_title(book, progress_map, volume_counts) do
    state =
      case book_progress(book, progress_map) do
        p when p in [nil, 0.0] -> gettext("unread")
        p when p >= 1.0 -> gettext("read")
        p -> gettext("%{percent}% read", percent: round(p * 100))
      end

    [Formatters.book_number_label(book, volume_counts), book.title, state] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  defp sort_books(books, "title_asc"), do: Enum.sort_by(books, & &1.title)
  defp sort_books(books, "title_desc"), do: Enum.sort_by(books, & &1.title, :desc)
  defp sort_books(books, "year_asc"), do: Enum.sort_by(books, &(&1.year || 0))
  defp sort_books(books, "year_desc"), do: Enum.sort_by(books, &(&1.year || 0), :desc)
  defp sort_books(books, "added_asc"), do: Enum.sort_by(books, & &1.inserted_at, NaiveDateTime)

  defp sort_books(books, "added_desc"),
    do: Enum.sort_by(books, & &1.inserted_at, {:desc, NaiveDateTime})

  defp sort_books(books, "issue_desc"), do: books |> Library.sort_reading_order() |> Enum.reverse()
  defp sort_books(books, _), do: Library.sort_reading_order(books)

  @impl true
  def render(assigns) do
    ~H"""
    <% issue_sorted = sort_books(@series.books, "issue_asc") %>
    <% volume_counts = Library.volume_counts(@series.books) %>
    <% first_book = List.first(issue_sorted) %>
    <% issue_count = length(issue_sorted) %>
    <% read_count = Enum.count(issue_sorted, &((book_progress(&1, @progress_map) || 0.0) >= 1.0)) %>
    <%!-- A folder cover.* outranks the first issue's cover, as on list pages --%>
    <% has_cover = @folder_cover? || (@cover_book && @cover_book.cover) %>
    <% cover_base =
      if @folder_cover?, do: ~p"/api/series/#{@series.id}/cover", else: has_cover && ~p"/api/books/#{@cover_book.id}/cover" %>
    <.page cover_src={has_cover && "#{cover_base}?s=s"}>
      <.crumbs crumbs={[
        {gettext("Home"), "/"},
        {@library.name, ~p"/library/#{@library}"},
        {@series.name, nil}
      ]}>
        <:actions :if={@current_user.role == :admin}>
          <.ink_menu id="series-admin-menu">
            <:trigger class="flex items-center gap-1.5 px-3 h-8 text-xs font-medium rounded-full bg-fg/5 hover:bg-fg/15 text-fg-soft hover:text-fg backdrop-blur-sm transition-colors">
              <.icon name="lucide-settings" class="w-3.5 h-3.5" /> {gettext("Admin")}
              <.icon name="lucide-chevron-down" class="w-3 h-3" />
            </:trigger>
            <.menu_item icon="lucide-pencil" phx-click="open_edit_dialog">{gettext("Edit metadata")}</.menu_item>
            <.needs_sources ready={@sources_ready} class="block">
              <.menu_item icon="lucide-cloud-download" phx-click="fetch_metadata" disabled={!@sources_ready}>
                {gettext("Fetch metadata")}
              </.menu_item>
              <.menu_item icon="lucide-scan-search" phx-click="open_identify_dialog" disabled={!@sources_ready}>
                {gettext("Identify series…")}
              </.menu_item>
            </.needs_sources>
            <.menu_item
              icon={if @series.metadata_locked, do: "lucide-lock-open", else: "lucide-lock"}
              phx-click="toggle_metadata_lock"
            >
              {if @series.metadata_locked, do: gettext("Unlock metadata"), else: gettext("Lock metadata")}
            </.menu_item>
            <.menu_separator />
            <.menu_item
              :if={@series.publishers != []}
              icon="lucide-arrow-down-to-line"
              phx-click="open_push_publishers_dialog"
            >
              {gettext("Push publishers to issues…")}
            </.menu_item>
            <.menu_item
              :if={@series.books != []}
              icon="lucide-shield"
              phx-click="open_push_age_rating_dialog"
            >
              {gettext("Push age rating to issues…")}
            </.menu_item>
            <.menu_item
              :if={@series.books != []}
              icon="lucide-languages"
              phx-click="open_push_language_dialog"
            >
              {gettext("Push language to issues…")}
            </.menu_item>
            <.menu_item
              :if={@series.books != []}
              icon="lucide-hash"
              phx-click="open_issue_numbers_dialog"
            >
              {gettext("Issue numbers from filenames…")}
            </.menu_item>
            <.menu_separator />
            <.menu_item
              icon={if @scanning, do: "lucide-loader-circle", else: "lucide-refresh-cw"}
              icon_class={if @scanning, do: "animate-spin"}
              phx-click="rescan_series"
            >
              {if @scanning, do: gettext("Scanning…"), else: gettext("Rescan series")}
            </.menu_item>
            <.menu_item
              icon={if @scanning, do: "lucide-loader-circle", else: "lucide-zap"}
              icon_class={if @scanning, do: "animate-spin"}
              tone="warning"
              phx-click="force_rescan_series"
            >
              {if @scanning, do: gettext("Scanning…"), else: gettext("Force rescan")}
            </.menu_item>
          </.ink_menu>
        </:actions>
      </.crumbs>

      <%!-- Hero: fanned cover stack, giant issue count behind the title --%>
      <header class="relative flex flex-col items-center sm:flex-row sm:items-end gap-8 sm:gap-14 pt-2">
        <.ghost_numeral
          :if={issue_count > 1}
          class="hidden sm:block absolute -top-4 right-0 text-[11rem] md:text-[15rem]"
        >
          {issue_count}
        </.ghost_numeral>

        <.hero_cover
          id={"series-cover-#{@series.id}"}
          src={has_cover && "#{cover_base}?s=l"}
          full_src={has_cover && "#{cover_base}?s=xl"}
          alt={@series.name}
          blurhash={if @folder_cover?, do: @folder_cover_blurhash, else: has_cover && @cover_book.cover.blurhash}
          stack={
            if User.ui_setting(@current_user, "data_saver") == "on",
              do: [],
              else:
                issue_sorted
                |> Enum.filter(&(&1.cover && (@folder_cover? || !@cover_book || &1.id != @cover_book.id)))
                |> Enum.take(2)
                |> Enum.map(&~p"/api/books/#{&1.id}/cover?s=m")
          }
        />

        <div class="relative min-w-0 flex-1 text-center sm:text-left sm:pb-2">
          <.eyebrow :if={@book_publishers != []} class="rise mb-3" style="--i:1">
            <%= for {pub, idx} <- Enum.with_index(@book_publishers) do %>
              <span :if={idx > 0} class="text-fg/25"> / </span>
              <.link navigate={~p"/publisher/#{pub}"} class="hover:text-fg transition-colors">{pub.name}</.link>
            <% end %>
          </.eyebrow>

          <.display_heading level={1} size="hero" class="rise" style="--i:2">
            {@series.name}
          </.display_heading>

          <div
            class="rise flex items-center justify-center sm:justify-start flex-wrap gap-x-3 gap-y-1 mt-4 text-sm text-fg-soft"
            style="--i:3"
          >
            <span :if={yr = year_range(@series)} class="tabular-nums">{yr}</span>
            <%= if @series.ongoing do %>
              <span class="inline-flex items-center gap-1.5 text-success">
                <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse"></span> {gettext("Ongoing")}
              </span>
            <% else %>
              <span class="inline-flex items-center gap-1.5 text-muted">
                <span class="w-1.5 h-1.5 rounded-full bg-faint"></span> {gettext("Completed")}
              </span>
            <% end %>
            <span class="tabular-nums">
              {ngettext("1 issue", "%{count} issues", issue_count)}
            </span>
          </div>

          <%!-- Read buttons --%>
          <%= if @continue_book do %>
            <% has_progress = (@progress_map[@continue_book.id] || 0) > 0 %>
            <div class="rise flex items-center justify-center sm:justify-start gap-5 flex-wrap mt-7" style="--i:4">
              <.ink_button navigate={~p"/read/#{@continue_book}"}>
                <.icon name="lucide-play" class="w-4 h-4" />
                {if has_progress, do: gettext("Continue"), else: gettext("Start Reading")}
                <span :if={lbl = Formatters.book_number_label(@continue_book, volume_counts)} class="text-ink">{lbl}</span>
              </.ink_button>
              <.text_link
                :if={has_progress && first_book && first_book.id != @continue_book.id}
                tone="subtle"
                navigate={~p"/read/#{first_book}"}
              >
                <.icon name="lucide-rotate-ccw" class="w-4 h-4" /> {gettext("Read from #1")}
              </.text_link>
            </div>
          <% end %>
        </div>
      </header>

      <%!-- The run: solid = read, striped = in progress, dark = unread --%>
      <section :if={issue_count > 1} class="rise" style="--i:5">
        <div class="flex items-baseline justify-between mb-3">
          <.eyebrow tag="h2" size="sm" tone="muted">{gettext("The Run")}</.eyebrow>
          <p class="tabular-nums leading-none">
            <span class="font-display font-black text-3xl text-fg">{read_count}</span>
            <span class="text-muted text-sm">{gettext("/ %{count} read", count: issue_count)}</span>
          </p>
        </div>
        <div class={["flex items-stretch h-5", if(issue_count <= 150, do: "gap-[2px]", else: "gap-0")]}>
          <.link
            :for={b <- issue_sorted}
            navigate={~p"/book/#{b}"}
            title={run_segment_title(b, @progress_map, volume_counts)}
            class="flex-1 min-w-0 rounded-[2px] overflow-hidden bg-fg/[0.07] transition-[filter] duration-100 hover:brightness-125"
          >
            <span class="block h-full" style={run_fill_style(b, @progress_map)} />
          </.link>
        </div>
      </section>

      <%!-- Summary --%>
      <section :if={@summary_info} class="max-w-3xl">
        <p class="text-[15px] text-fg-soft leading-7 whitespace-pre-line">{@summary_info.text}</p>
        <p :if={@summary_info.source} class="mt-2 text-xs text-muted italic">
          {gettext("From issue %{issue}", issue: @summary_info.source)}
        </p>
      </section>

      <% series_age_rating = common_age_rating(@series.books) %>
      <.indicia>
        <:item label={gettext("Pages")} show={@total_pages > 0}>
          {@total_pages
          |> Integer.to_string()
          |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")}
        </:item>
        <:item
          label={gettext("Size")}
          show={
            User.ui_setting(@current_user, "extended_book_info") == "on" &&
              Format.file_size(@total_size) != nil
          }
        >
          {Format.file_size(@total_size)}
        </:item>
        <:item label={gettext("Age Rating")} show={series_age_rating != nil}>
          {Formatters.format_age_rating(series_age_rating)}
        </:item>
        <:item label={gettext("Volume")} show={@series.volume != nil}>
          {gettext("Vol. %{volume}", volume: @series.volume)}
        </:item>
        <:item label={gettext("Language")} show={@series.language != nil}>
          {Formatters.language_name(@series.language)}
        </:item>
        <:item label={gettext("Metadata")} show={@series.metadata_locked}>
          <span class="inline-flex items-center gap-1 text-warn/90">
            <.icon name="lucide-lock" class="w-3 h-3" /> {gettext("Locked")}
          </span>
        </:item>
      </.indicia>

      <% sd = @series_details %>
      <.details_panel
        id="series-details"
        credits={Roles.group_counts(sd.creators)}
        facts={series_facts(sd.series)}
        genres={sd.genres}
        tags={sd.tags}
        arcs={sd.arcs}
        characters={sd.characters}
        teams={sd.teams}
        locations={sd.locations}
        universes={sd.universes}
      />

      <%!-- Issues --%>
      <.section title={gettext("Issues")} count={issue_count}>
        <:actions>
          <form id="issue-sort" phx-change="sort">
            <.ink_select
              id="issue-sort-input"
              name="value"
              label={gettext("Sort issues")}
              size="sm"
              value={@sort}
              options={Enum.slice(sort_options(:issues), 2, 2) ++ sort_options(:titles)}
            />
          </form>
        </:actions>
        <.cover_grid cols="narrow">
          <%= for book <- @books do %>
            <.media_card
              navigate={~p"/book/#{book}"}
              title={book.title}
              cover_url={~p"/api/books/#{book.id}/cover"}
              size="m"
              subtitle={book.year && to_string(book.year)}
              badge={Formatters.book_number_label(book, volume_counts)}
              progress={book_progress(book, @progress_map)}
              type={:book}
              blurhash={book.cover && book.cover.blurhash}
            />
          <% end %>
        </.cover_grid>
      </.section>

      <%!-- Folder path --%>
      <div
        :if={@current_user.role == :admin && @series.path}
        class="flex items-start gap-1.5 text-[11px] font-mono text-muted break-all leading-snug"
      >
        <.icon name="lucide-folder" class="w-3 h-3 flex-shrink-0 mt-0.5 text-line" />
        {relative_folder(@series, @library)}
      </div>
    </.page>

    <%!-- Identify Dialog --%>
    <%= if @current_user.role == :admin && @show_identify_dialog do %>
      <.live_component module={StashixWeb.IdentifyComponent} id="identify-series" target={@series} />
    <% end %>

    <%!-- Edit Metadata Dialog --%>
    <.live_component
      :if={@current_user.role == :admin && @show_edit_dialog}
      module={StashixWeb.SeriesEditComponent}
      id="edit-series"
      series={@series}
      all_publishers={@all_publishers}
      folder={@series.path && relative_folder(@series, @library)}
    />

    <%= if @current_user.role == :admin && @show_push_publishers_dialog do %>
      <.dialog
        id="push-publishers-dialog"
        title={gettext("Push publishers to issues")}
        on_close={JS.push("close_push_publishers_dialog")}
      >
        <:description>
          {gettext("Apply the series publisher(s) to all issues. Choose how to handle issues that already have publishers.")}
        </:description>

        <div class="space-y-2 mt-3">
          <%= for {mode, label, desc} <- [
            {:replace, gettext("Replace"),
             gettext("Remove each issue's current publishers and set them to match the series.")},
            {:merge, gettext("Add"), gettext("Add the series publishers to each issue, keeping any they already have.")},
            {:fill, gettext("Fill empty"), gettext("Only update issues that have no publisher set.")}
          ] do %>
            <label class={[
              "flex items-start gap-3 rounded-md border p-3 cursor-pointer transition-colors",
              if(@push_publishers_mode == mode,
                do: "border-violet-500 bg-violet-500/10",
                else: "border-line hover:border-line-strong"
              )
            ]}>
              <input
                type="radio"
                name="push_publishers_mode"
                value={mode}
                checked={@push_publishers_mode == mode}
                phx-click="set_push_publishers_mode"
                phx-value-mode={mode}
                class="mt-0.5 accent-violet-500"
              />
              <div>
                <p class="text-sm font-medium text-fg">{label}</p>
                <p class="text-xs text-muted mt-0.5">{desc}</p>
              </div>
            </label>
          <% end %>
        </div>

        <%= if @push_publishers_preview do %>
          <% affected_count = length(@push_publishers_preview.affected) %>
          <% total = affected_count + @push_publishers_preview.unchanged %>
          <div class="mt-4">
            <button
              type="button"
              class="flex items-center gap-1.5 text-xs text-muted hover:text-fg-soft transition-colors w-full"
              phx-click="toggle_push_preview"
            >
              <.icon
                name={if @show_push_preview, do: "lucide-chevron-down", else: "lucide-chevron-right"}
                class="w-3.5 h-3.5"
              />
              <span>{gettext("Preview")}</span>
              <span class={["ml-1 font-medium", if(affected_count > 0, do: "text-accent", else: "text-faint")]}>
                <%= if affected_count == 0 do %>
                  {gettext("no changes")}
                <% else %>
                  {will_change(affected_count, total)}
                <% end %>
              </span>
            </button>

            <div :if={@show_push_preview} class="mt-2 rounded-md border border-line overflow-hidden">
              <%= if affected_count == 0 do %>
                <p class="px-3 py-4 text-sm text-muted text-center">
                  {gettext("All issues already match — no changes needed.")}
                </p>
              <% else %>
                <%!-- header row --%>
                <div class="grid grid-cols-[2rem_1fr_auto_1fr] items-center gap-x-2 px-3 py-1.5 bg-raised/60 border-b border-line text-[10px] font-semibold uppercase tracking-wider text-faint">
                  <span></span>
                  <span class="col-span-1">{gettext("Before")}</span>
                  <span></span>
                  <span>{gettext("After")}</span>
                </div>
                <div class="max-h-52 overflow-y-auto divide-y divide-line/80">
                  <%= for entry <- @push_publishers_preview.affected do %>
                    <div class="grid grid-cols-[2rem_1fr_auto_1fr] items-center gap-x-2 px-3 py-2 text-xs">
                      <span class="text-faint tabular-nums">
                        {if entry.book.issue_number, do: "##{entry.book.issue_number}", else: "—"}
                      </span>
                      <span class="text-faint italic truncate">
                        {if entry.from == [], do: gettext("none"), else: Enum.map_join(entry.from, ", ", & &1.name)}
                      </span>
                      <.icon name="lucide-arrow-right" class="w-3 h-3 text-faint shrink-0" />
                      <span class="text-fg truncate">
                        {Enum.map_join(entry.to, ", ", & &1.name)}
                      </span>
                    </div>
                  <% end %>
                </div>
                <%= if @push_publishers_preview.unchanged > 0 do %>
                  <p class="px-3 py-1.5 text-xs text-faint border-t border-line">
                    {ngettext(
                      "1 issue already up to date",
                      "%{count} issues already up to date",
                      @push_publishers_preview.unchanged
                    )}
                  </p>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <.dialog_footer>
          <.ink_button type="button" variant="ghost" size="md" phx-click="close_push_publishers_dialog">
            {gettext("Cancel")}
          </.ink_button>
          <.ink_button type="button" size="md" phx-click="push_publishers_to_issues">
            {gettext("Push publishers")}
          </.ink_button>
        </.dialog_footer>
      </.dialog>
    <% end %>

    <.push_language_dialog
      :if={@current_user.role == :admin && @push_language}
      language={@push_language}
      mode={@push_language_mode}
      preview={@push_language_preview}
    />

    <.issue_numbers_dialog
      :if={@current_user.role == :admin && @issue_numbers_preview}
      preview={@issue_numbers_preview}
      skipped={@issue_numbers_skipped}
    />

    <%= if @current_user.role == :admin && @show_push_age_rating_dialog do %>
      <.dialog
        id="push-age-rating-dialog"
        title={gettext("Push age rating to issues")}
        on_close={JS.push("close_push_age_rating_dialog")}
      >
        <:description>
          {gettext("Apply an age rating to all issues in this series.")}
        </:description>

        <div class="space-y-4 mt-3">
          <div>
            <label class="block mb-1.5 text-[10px] font-bold tracking-[0.18em] uppercase text-fg-soft">
              {gettext("Rating to apply")}
            </label>
            <form phx-change="set_push_age_rating_target">
              <.ink_select
                id="push-age-rating-select"
                name="rating"
                label={gettext("Age rating")}
                variant="field"
                value={@push_age_rating_target}
                options={Enum.map(@age_ratings, &{Formatters.format_age_rating(&1), Atom.to_string(&1)})}
              />
            </form>
          </div>

          <div class="space-y-2">
            <%= for {mode, label, desc} <- [
              {:replace, gettext("Replace"), gettext("Overwrite the age rating on all issues.")},
              {:fill, gettext("Fill unknown"), gettext("Only update issues that are currently unrated.")}
            ] do %>
              <label class={[
                "flex items-start gap-3 rounded-md border p-3 cursor-pointer transition-colors",
                if(@push_age_rating_mode == mode,
                  do: "border-violet-500 bg-violet-500/10",
                  else: "border-line hover:border-line-strong"
                )
              ]}>
                <input
                  type="radio"
                  name="push_age_rating_mode"
                  value={mode}
                  checked={@push_age_rating_mode == mode}
                  phx-click="set_push_age_rating_mode"
                  phx-value-mode={mode}
                  class="mt-0.5 accent-violet-500"
                />
                <div>
                  <p class="text-sm font-medium text-fg">{label}</p>
                  <p class="text-xs text-muted mt-0.5">{desc}</p>
                </div>
              </label>
            <% end %>
          </div>
        </div>

        <%= if @push_age_rating_preview do %>
          <% ar_affected = length(@push_age_rating_preview.affected) %>
          <% ar_total = ar_affected + @push_age_rating_preview.unchanged %>
          <div class="mt-4">
            <button
              type="button"
              class="flex items-center gap-1.5 text-xs text-muted hover:text-fg-soft transition-colors w-full"
              phx-click="toggle_push_age_rating_preview"
            >
              <.icon
                name={if @show_push_age_rating_preview, do: "lucide-chevron-down", else: "lucide-chevron-right"}
                class="w-3.5 h-3.5"
              />
              <span>{gettext("Preview")}</span>
              <span class={[
                "ml-1 font-medium",
                if(ar_affected > 0, do: "text-accent", else: "text-faint")
              ]}>
                <%= if ar_affected == 0 do %>
                  {gettext("no changes")}
                <% else %>
                  {will_change(ar_affected, ar_total)}
                <% end %>
              </span>
            </button>

            <div :if={@show_push_age_rating_preview} class="mt-2 rounded-md border border-line overflow-hidden">
              <%= if ar_affected == 0 do %>
                <p class="px-3 py-4 text-sm text-muted text-center">
                  {gettext("All issues already match — no changes needed.")}
                </p>
              <% else %>
                <div class="grid grid-cols-[2rem_1fr_auto_1fr] items-center gap-x-2 px-3 py-1.5 bg-raised/60 border-b border-line text-[10px] font-semibold uppercase tracking-wider text-faint">
                  <span></span>
                  <span>{gettext("Before")}</span>
                  <span></span>
                  <span>{gettext("After")}</span>
                </div>
                <div class="max-h-52 overflow-y-auto divide-y divide-line/80">
                  <%= for entry <- @push_age_rating_preview.affected do %>
                    <div class="grid grid-cols-[2rem_1fr_auto_1fr] items-center gap-x-2 px-3 py-2 text-xs">
                      <span class="text-faint tabular-nums">
                        {if entry.book.issue_number, do: "##{entry.book.issue_number}", else: "—"}
                      </span>
                      <span class="text-faint italic truncate">
                        {short_age_label(entry.from)}
                      </span>
                      <.icon name="lucide-arrow-right" class="w-3 h-3 text-faint shrink-0" />
                      <span class="text-fg truncate">
                        {short_age_label(entry.to)}
                      </span>
                    </div>
                  <% end %>
                </div>
                <%= if @push_age_rating_preview.unchanged > 0 do %>
                  <p class="px-3 py-1.5 text-xs text-faint border-t border-line">
                    {ngettext(
                      "1 issue already up to date",
                      "%{count} issues already up to date",
                      @push_age_rating_preview.unchanged
                    )}
                  </p>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <.dialog_footer>
          <.ink_button type="button" variant="ghost" size="md" phx-click="close_push_age_rating_dialog">
            {gettext("Cancel")}
          </.ink_button>
          <.ink_button type="button" size="md" phx-click="push_age_rating_to_issues">
            {gettext("Push age rating")}
          </.ink_button>
        </.dialog_footer>
      </.dialog>
    <% end %>
    """
  end

  # Preview line of the push dialogs.
  defp will_change(changed, total) do
    ngettext("%{changed} of 1 issue will change", "%{changed} of %{count} issues will change", total, changed: changed)
  end

  defp short_age_label(:unknown), do: gettext("Unrated")
  defp short_age_label(:everyone), do: gettext("Everyone")
  defp short_age_label(:teen), do: gettext("Teen")
  defp short_age_label(:teen_plus), do: gettext("Teen+")
  defp short_age_label(:mature), do: gettext("Mature")
  defp short_age_label(:adult), do: gettext("Adult")
  defp short_age_label(:explicit), do: gettext("Explicit")
  defp short_age_label(nil), do: gettext("Unrated")
  defp short_age_label(other), do: to_string(other)

  attr :language, :string, required: true
  attr :mode, :atom, required: true
  attr :preview, :map, required: true

  defp push_language_dialog(assigns) do
    ~H"""
    <.dialog
      id="push-language-dialog"
      title={gettext("Push language to issues")}
      on_close={JS.push("close_push_language_dialog")}
    >
      <:description>
        {gettext("Set the language of every issue in this series. Issues that lock their language are skipped.")}
      </:description>

      <div class="space-y-4 mt-3">
        <form id="push-language-form" phx-change="set_push_language">
          <.field label={gettext("Language")}>
            <.ink_select
              id="push-language-select"
              name="language"
              label={gettext("Language")}
              variant="field"
              value={@language}
              options={Formatters.language_options(@language)}
              searchable
            />
          </.field>
        </form>

        <div class="space-y-2">
          <label
            :for={
              {mode, label, desc} <- [
                {:replace, gettext("Replace"), gettext("Overwrite the language on all issues.")},
                {:fill, gettext("Fill empty"), gettext("Only set it on issues that have no language.")}
              ]
            }
            class={[
              "flex items-start gap-3 rounded-md border p-3 cursor-pointer transition-colors",
              if(@mode == mode, do: "border-ink bg-ink/10", else: "border-line hover:border-line-strong")
            ]}
          >
            <input
              type="radio"
              name="push_language_mode"
              value={mode}
              checked={@mode == mode}
              phx-click="set_push_language_mode"
              phx-value-mode={mode}
              class="mt-0.5 accent-ink"
            />
            <div>
              <p class="text-sm font-medium text-fg">{label}</p>
              <p class="text-xs text-muted mt-0.5">{desc}</p>
            </div>
          </label>
        </div>

        <% affected = length(@preview.affected) %>
        <div class="rounded-md border border-line overflow-hidden">
          <p class="px-3 py-2 text-xs text-muted bg-raised/60 border-b border-line">
            <%= if affected == 0 do %>
              {gettext("All issues already match — no changes needed.")}
            <% else %>
              {will_change(affected, affected + @preview.unchanged)}
            <% end %>
          </p>
          <div :if={affected > 0} class="max-h-52 overflow-y-auto divide-y divide-line/80">
            <div
              :for={entry <- @preview.affected}
              class="grid grid-cols-[2.5rem_1fr_auto_1fr] items-center gap-x-2 px-3 py-2 text-xs"
            >
              <span class="text-faint tabular-nums">
                {if entry.book.issue_number, do: "##{entry.book.issue_number}", else: "—"}
              </span>
              <span class="text-faint italic truncate">{Formatters.language_name(entry.from) || gettext("None")}</span>
              <.icon name="lucide-arrow-right" class="w-3 h-3 text-faint shrink-0" />
              <span class="text-fg truncate">{Formatters.language_name(entry.to)}</span>
            </div>
          </div>
        </div>
      </div>

      <.dialog_footer>
        <.ink_button type="button" variant="ghost" size="md" phx-click="close_push_language_dialog">{gettext("Cancel")}</.ink_button>
        <.ink_button type="button" size="md" phx-click="push_language_to_issues" disabled={affected == 0}>
          {gettext("Push to issues")}
        </.ink_button>
      </.dialog_footer>
    </.dialog>
    """
  end

  attr :preview, :map, required: true
  attr :skipped, :any, required: true

  defp issue_numbers_dialog(assigns) do
    ~H"""
    <.dialog
      id="issue-numbers-dialog"
      title={gettext("Issue numbers from filenames")}
      on_close={JS.push("close_issue_numbers_dialog")}
    >
      <:description>
        {gettext(
          "Set each issue's number from its file name, and write it into the file so a rescan keeps it. Issues that lock their number are skipped."
        )}
      </:description>

      <% affected = length(@preview.affected) %>
      <% selected = Enum.count(@preview.affected, &(not MapSet.member?(@skipped, &1.book.id))) %>
      <% total = affected + @preview.unchanged + @preview.unparsed %>
      <div class="mt-3 rounded-md border border-line overflow-hidden">
        <p class="px-3 py-2 text-xs text-muted bg-raised/60 border-b border-line">
          <%= if affected == 0 do %>
            {gettext("All issues already match their file names — no changes needed.")}
          <% else %>
            {ngettext(
              "%{changed} of 1 issue differs from its file name",
              "%{changed} of %{count} issues differ from their file names",
              total,
              changed: affected
            )}
          <% end %>
        </p>
        <div :if={affected > 0} class="max-h-72 overflow-y-auto divide-y divide-line/80">
          <label
            :for={entry <- @preview.affected}
            class="grid grid-cols-[1rem_1fr_auto_auto_auto] items-center gap-x-2.5 px-3 py-2 text-xs cursor-pointer hover:bg-raised/40"
          >
            <input
              type="checkbox"
              checked={not MapSet.member?(@skipped, entry.book.id)}
              phx-click="toggle_issue_number"
              phx-value-id={entry.book.id}
              class="accent-ink"
            />
            <span class="text-fg-soft truncate" title={entry.file}>{entry.file}</span>
            <span class="text-faint italic tabular-nums">{if entry.from, do: "##{entry.from}", else: "—"}</span>
            <.icon name="lucide-arrow-right" class="w-3 h-3 text-faint shrink-0" />
            <span class="text-fg tabular-nums font-medium">{"##{entry.to}"}</span>
          </label>
        </div>
        <p :if={@preview.unparsed > 0} class="px-3 py-1.5 text-xs text-faint border-t border-line">
          {ngettext(
            "1 file has no number in its name — left as is",
            "%{count} files have no number in their names — left as is",
            @preview.unparsed
          )}
        </p>
      </div>

      <.dialog_footer>
        <.ink_button type="button" variant="ghost" size="md" phx-click="close_issue_numbers_dialog">{gettext("Cancel")}</.ink_button>
        <.ink_button type="button" size="md" phx-click="apply_issue_numbers" disabled={selected == 0}>
          {ngettext("Update 1 issue", "Update %{count} issues", selected)}
        </.ink_button>
      </.dialog_footer>
    </.dialog>
    """
  end
end
