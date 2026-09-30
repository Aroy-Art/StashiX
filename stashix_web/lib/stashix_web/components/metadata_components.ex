defmodule StashixWeb.MetadataComponents do
  @moduledoc "Pieces for showing MetronInfo details (credits, characters, arcs, …) on book and series pages."
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import StashixUi.Icon, only: [icon: 1]

  @doc "Compact 'Writer … · Artist …' line."
  attr :groups, :list, required: true, doc: "[{heading, [name | {name, count}]}]"

  def credits_line(assigns) do
    ~H"""
    <div :if={@groups != []} class="flex flex-wrap gap-x-6 gap-y-2 text-sm">
      <div :for={{label, names} <- @groups} class="min-w-0">
        <span class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mr-1.5">{label}</span>
        <span class="text-gray-300">
          <span :for={{n, i} <- Enum.with_index(names)}>
            <.link
              navigate={"/search?creator=#{entry_id(n)}"}
              class="hover:text-white hover:underline transition-colors"
            >{entry_name(n)}</.link><span :if={i < length(names) - 1}>, </span>
          </span>
        </span>
      </div>
    </div>
    """
  end

  @doc "Show more / less toggle with a collapsible panel. Toggling is client-side only."
  attr :id, :string, required: true
  slot :inner_block, required: true

  def expander(assigns) do
    ~H"""
    <div>
      <button
        type="button"
        phx-click={
          JS.toggle(to: "##{@id}")
          |> JS.toggle_class("rotate-180", to: "##{@id}-chevron")
          |> JS.toggle(to: "##{@id}-more", display: "inline")
          |> JS.toggle(to: "##{@id}-less", display: "inline")
        }
        class="group inline-flex items-center gap-1.5 text-xs font-medium text-gray-500 hover:text-gray-200 transition-colors"
        aria-controls={@id}
      >
        <span id={"#{@id}-more"} class="group-hover:text-gray-200">More info</span>
        <span id={"#{@id}-less"} class="hidden group-hover:text-gray-200">Less info</span>
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform duration-200">
          <.icon name="lucide-chevron-down" class="w-3.5 h-3.5" />
        </span>
      </button>
      <div id={@id} class="hidden mt-5 space-y-6 border-t border-gray-800/60 pt-5">
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
        <p class="text-[10px] text-gray-500 uppercase tracking-[0.1em] mt-0.5">{@role}</p>
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
      <h3 class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-500 mb-3">{@label}</h3>
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
        <dt class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-0.5">{label}</dt>
        <dd class="text-gray-300 break-words">{value}</dd>
      </div>
    </dl>
    """
  end

  @doc "Chip list; items are names or `{name, count}`. Long lists are cut with a '+N' marker."
  attr :items, :list, required: true
  attr :limit, :integer, default: 40

  def chips(assigns) do
    {shown, rest} = Enum.split(assigns.items, assigns.limit)
    assigns = assign(assigns, shown: shown, rest: length(rest))

    ~H"""
    <div class="flex flex-wrap gap-1.5">
      <span
        :for={item <- @shown}
        class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-gray-800/70 border border-gray-800 text-xs text-gray-300"
      >
        {entry_name(item)}
        <span :if={entry_count(item)} class="text-gray-600">{entry_count(item)}</span>
      </span>
      <span :if={@rest > 0} class="px-2 py-0.5 text-xs text-gray-600">+{@rest} more</span>
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
