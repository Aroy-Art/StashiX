defmodule StashixWeb.MetadataComponents do
  @moduledoc "Pieces for showing MetronInfo details (credits, characters, arcs, …) on book and series pages."
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Stashix.Metadata.Roles
  import StashixWeb.UI.Icon, only: [icon: 1]
  import StashixWeb.UI.Ink, only: [eyebrow: 1, chip: 1]

  @doc """
  Headline credits plus a "More info" expander holding everything else.
  Shared by the book and series pages; renders nothing when there is nothing to show.
  """
  attr :id, :string, required: true
  attr :credits, :list, default: [], doc: "[{role, [{name, id} | {name, count, id}]}]"
  attr :facts, :list, default: [], doc: "[{label, value}]"
  attr :genres, :list, default: []
  attr :tags, :list, default: []
  attr :arcs, :list, default: []
  attr :characters, :list, default: []
  attr :teams, :list, default: []
  attr :locations, :list, default: []
  attr :universes, :list, default: []
  attr :reprints, :list, default: []
  attr :links, :list, default: [], doc: "[{label, href | nil}]"
  attr :notes, :string, default: nil

  def details_panel(assigns) do
    assigns =
      assign(assigns,
        headline: Roles.headline(assigns.credits),
        facts: Enum.reject(assigns.facts, fn {_, v} -> v in [nil, "", []] end),
        notes: assigns.notes || ""
      )

    lists =
      ~w(credits facts genres tags arcs characters teams locations universes reprints links)a

    assigns =
      assign(assigns, show: assigns.notes != "" || Enum.any?(lists, &(assigns[&1] != [])))

    ~H"""
    <div :if={@show} class="space-y-5">
      <.credits_line groups={@headline} />
      <.expander id={@id}>
        <.detail_section label="Credits" show={@credits != []}>
          <div class="grid grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-3">
            <%= for {role, entries} <- @credits, entry <- entries do %>
              <.creator_card name={entry_name(entry)} role={credit_role(role, entry)} creator_id={entry_id(entry)} />
            <% end %>
          </div>
        </.detail_section>

        <.detail_grid entries={@facts} />

        <.detail_section label="Genres" show={@genres != []}>
          <.chips items={@genres} search_param="genre" />
        </.detail_section>

        <.detail_section label="Tags" show={@tags != []}>
          <.chips items={@tags} search_param="tag" />
        </.detail_section>

        <.detail_section label="Story Arcs" show={@arcs != []}>
          <.chips items={@arcs} />
        </.detail_section>

        <.detail_section label="Characters" show={@characters != []}>
          <.chips items={@characters} search_param="character" />
        </.detail_section>

        <.detail_section label="Teams" show={@teams != []}>
          <.chips items={@teams} search_param="team" />
        </.detail_section>

        <.detail_section label="Locations" show={@locations != []}>
          <.chips items={@locations} search_param="location" />
        </.detail_section>

        <.detail_section label="Universes" show={@universes != []}>
          <.chips items={@universes} />
        </.detail_section>

        <.detail_section label="Reprints" show={@reprints != []}>
          <.chips items={@reprints} />
        </.detail_section>

        <.detail_section label="Links" show={@links != []}>
          <div class="flex flex-wrap gap-1.5">
            <%= for {label, href} <- @links do %>
              <.chip :if={href} href={href} target="_blank" rel="noopener noreferrer">
                {label} <.icon name="lucide-external-link" class="w-3 h-3 shrink-0" />
              </.chip>
              <.chip :if={!href}>{label}</.chip>
            <% end %>
          </div>
        </.detail_section>

        <.detail_section label="Notes" show={@notes != ""}>
          <p class="text-sm text-gray-400 leading-relaxed whitespace-pre-line break-words">{@notes}</p>
        </.detail_section>
      </.expander>
    </div>
    """
  end

  defp credit_role(role, {_name, count, _id}) when count > 1, do: "#{role} · #{count} issues"
  defp credit_role(role, _entry), do: role

  @doc "Headline credits as one column per role; long lists are cut with a '+N more' marker."
  attr :groups, :list, required: true, doc: "[{heading, [name | {name, count}]}]"
  attr :limit, :integer, default: 3

  def credits_line(assigns) do
    ~H"""
    <dl :if={@groups != []} class="grid grid-cols-3 gap-x-4 gap-y-5 sm:gap-x-10">
      <div :for={{label, names} <- @groups} class="min-w-0 border-l-2 border-white/10 pl-3 sm:pl-4">
        <.eyebrow tag="dt" size="sm" tone="ink" class="mb-1.5">{label}</.eyebrow>
        <dd class="text-sm text-gray-200 leading-6">
          <.link
            :for={n <- Enum.take(names, @limit)}
            navigate={"/search?creator=#{entry_id(n)}"}
            class="block truncate hover:text-white hover:underline underline-offset-4 transition-colors"
          >
            {String.trim(entry_name(n))}
          </.link>
          <span :if={length(names) > @limit} class="block text-xs text-gray-400">
            +{length(names) - @limit} more
          </span>
        </dd>
      </div>
    </dl>
    """
  end

  @doc "Show more / less toggle with a collapsible panel. Toggling is client-side only."
  attr :id, :string, required: true
  slot :inner_block, required: true

  def expander(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-4">
        <span class="h-px flex-1 bg-white/10"></span>
        <button
          type="button"
          phx-click={
            JS.toggle(to: "##{@id}")
            |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
            |> JS.toggle(to: "##{@id}-more", display: "inline")
            |> JS.toggle(to: "##{@id}-less", display: "inline")
          }
          class="inline-flex items-center gap-2 pl-4 pr-3 py-2 rounded-full border border-white/15 bg-white/5 text-xs font-bold tracking-[0.16em] uppercase text-gray-100 hover:border-ink hover:bg-ink/10 hover:text-white transition-colors"
          aria-controls={@id}
        >
          <span id={"#{@id}-more"}>More info</span>
          <span id={"#{@id}-less"} class="hidden">Less info</span>
          <span id={"#{@id}-chevron"} class="inline-flex text-ink transition-transform duration-200">
            <.icon name="lucide-chevron-down" class="w-4 h-4" />
          </span>
        </button>
        <span class="h-px flex-1 bg-white/10"></span>
      </div>
      <div id={@id} class="hidden mt-6 space-y-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Creator avatar card: circle with initials + name + role label."
  attr :name, :string, required: true
  attr :role, :string, required: true
  attr :creator_id, :string, default: nil

  def creator_card(assigns) do
    ~H"""
    <div class="flex items-center gap-3 min-w-0">
      <div class={[
        "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center text-[11px] font-bold text-white select-none",
        creator_avatar_color(@name)
      ]}>
        {creator_initials(@name)}
      </div>
      <div class="min-w-0">
        <.link
          :if={@creator_id}
          navigate={"/search?creator=#{@creator_id}"}
          class="text-sm text-gray-200 leading-tight truncate hover:text-white hover:underline transition-colors block"
        >{@name}</.link>
        <p :if={!@creator_id} class="text-sm text-gray-200 leading-tight truncate">{@name}</p>
        <p class="text-[10px] text-gray-400 uppercase tracking-[0.1em] mt-0.5">{@role}</p>
      </div>
    </div>
    """
  end

  @avatar_colors ~w(
    bg-violet-600 bg-blue-600 bg-emerald-600 bg-amber-600
    bg-rose-600 bg-teal-600 bg-orange-600 bg-pink-600
  )

  defp creator_avatar_color(name) do
    idx = name |> :erlang.phash2() |> rem(length(@avatar_colors))
    Enum.at(@avatar_colors, idx)
  end

  defp creator_initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  @doc "Labelled section inside an expander; hidden when empty."
  attr :label, :string, required: true
  attr :show, :boolean, default: true
  slot :inner_block, required: true

  def detail_section(assigns) do
    ~H"""
    <section :if={@show}>
      <.eyebrow tag="h3" size="xs" tone="muted" class="mb-3">{@label}</.eyebrow>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Key/value grid; entries with empty values are skipped."
  attr :entries, :list, required: true, doc: "[{label, value}]"

  def detail_grid(assigns) do
    assigns = assign(assigns, entries: Enum.reject(assigns.entries, fn {_, v} -> v in [nil, "", []] end))

    ~H"""
    <dl :if={@entries != []} class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-6 gap-y-3 text-sm">
      <div :for={{label, value} <- @entries} class="min-w-0">
        <.eyebrow tag="dt" size="xs" tone="muted" class="mb-0.5">{label}</.eyebrow>
        <dd class="text-gray-300 break-words">{value}</dd>
      </div>
    </dl>
    """
  end

  @doc """
  Chip list; items are names or `{name, count}`. Long lists are cut with a '+N' marker.
  With `search_param`, each chip links to the search page filtered on that param.
  """
  attr :items, :list, required: true
  attr :limit, :integer, default: 40
  attr :search_param, :string, default: nil

  def chips(assigns) do
    {shown, rest} = Enum.split(assigns.items, assigns.limit)
    assigns = assign(assigns, shown: shown, rest: length(rest))

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <%= for item <- @shown do %>
        <.chip
          :if={@search_param}
          navigate={"/search?" <> URI.encode_query(%{@search_param => entry_name(item)})}
          count={entry_count(item)}
        >
          {entry_name(item)}
        </.chip>
        <.chip :if={!@search_param} count={entry_count(item)}>{entry_name(item)}</.chip>
      <% end %>
      <span :if={@rest > 0} class="px-2 py-0.5 text-xs text-gray-400">+{@rest} more</span>
    </div>
    """
  end

  defp entry_name({name, _count, _id}), do: name
  defp entry_name({name, _}), do: name
  defp entry_name(name), do: name

  defp entry_count({_name, count, _id}) when count > 1, do: count
  defp entry_count({_name, count}) when count > 1, do: count
  defp entry_count(_), do: nil

  defp entry_id({_name, _count, id}), do: id
  defp entry_id({_name, id}) when is_binary(id), do: id
  defp entry_id(_), do: nil
end
