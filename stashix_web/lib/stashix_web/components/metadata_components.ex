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
        <span class="text-gray-300">{names |> Enum.map(&entry_name/1) |> Enum.join(", ")}</span>
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
        class="inline-flex items-center gap-1.5 text-xs font-medium text-gray-500 hover:text-gray-300 transition-colors"
        aria-controls={@id}
      >
        <span id={"#{@id}-more"}>Show more details</span>
        <span id={"#{@id}-less"} class="hidden">Show less</span>
        <span id={"#{@id}-chevron"} class="inline-flex transition-transform">
          <.icon name="lucide-chevron-down" class="w-3.5 h-3.5" />
        </span>
      </button>
      <div id={@id} class="hidden mt-4 space-y-5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Labelled section inside an expander; hidden when empty."
  attr :label, :string, required: true
  attr :show, :boolean, default: true
  slot :inner_block, required: true

  def detail_section(assigns) do
    ~H"""
    <section :if={@show}>
      <h3 class="text-[9px] font-bold tracking-[0.14em] uppercase text-gray-600 mb-2">{@label}</h3>
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

  defp entry_name({name, _count}), do: name
  defp entry_name(name), do: name

  defp entry_count({_name, count}) when count > 1, do: count
  defp entry_count(_), do: nil
end
