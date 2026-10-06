defmodule StashixWeb.UI.LongBox do
  @moduledoc """
  EXPERIMENT (see docs/ui-redesign-plan.md, "Long-box view"): series shown as
  comic spines standing in a long box instead of a grid of covers. Only the
  style guide at `/dev/ui` renders this so far.
  """
  use Phoenix.Component

  @doc "The box: a horizontally scrolling row of `spine/1`s standing on an ink edge."
  attr :id, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def long_box(assigns) do
    ~H"""
    <div id={@id} role="list" class={["long-box scrollbar-hide", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  One spine. Tinted from the cover's blurhash, as thick as the run is long,
  title running up it. Hovering or focusing pulls it out far enough to show
  the cover.
  """
  attr :navigate, :string, required: true
  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :blurhash, :string, default: nil
  attr :count, :integer, default: nil, doc: "issues in the series; sets the thickness"

  def spine(assigns) do
    count = assigns.count || 1

    assigns =
      assign(assigns,
        style:
          "--spine: #{blurhash_color(assigns.blurhash) || fallback_color(assigns.title)};" <>
            " --w: #{Float.round(1.5 + min(count, 60) * 0.03, 2)}rem;" <>
            " --h: #{88 + rem(:erlang.phash2(assigns.title), 5) * 3}%"
      )

    ~H"""
    <.link navigate={@navigate} role="listitem" aria-label={@title} class="spine" style={@style}>
      <img :if={@cover_url} src={@cover_url} alt="" loading="lazy" class="spine-cover" draggable="false" />
      <span class="spine-face">
        <span class="spine-title">{@title}</span>
        <span :if={@count} class="spine-count">{@count}</span>
      </span>
    </.link>
    """
  end

  @base83 ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
          |> Enum.with_index()
          |> Map.new()

  @doc """
  Average colour of a blurhash as a CSS colour, or nil. The average (DC)
  component is the four base-83 digits after the two header characters.
  """
  def blurhash_color(<<_header::binary-size(2), dc::binary-size(4), _rest::binary>>) do
    digits = for <<c <- dc>>, do: Map.get(@base83, c)

    if Enum.all?(digits) do
      value = Enum.reduce(digits, 0, &(&2 * 83 + &1))
      "rgb(#{Bitwise.bsr(value, 16)} #{value |> Bitwise.bsr(8) |> Bitwise.band(255)} #{Bitwise.band(value, 255)})"
    end
  end

  def blurhash_color(_), do: nil

  defp fallback_color(title), do: "oklch(0.6 0.14 #{rem(:erlang.phash2(title), 360)})"
end
