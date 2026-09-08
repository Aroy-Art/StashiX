defmodule StashixUi.Icon do
  @moduledoc """
  Renders icons from two supported sets via a unified `icon/1` component.

  The icon set is selected by the `name` prefix:

  | Prefix    | Library                                 | Rendering  |
  |-----------|-----------------------------------------|------------|
  | `lucide-` | [Lucide](https://lucide.dev)            | Inline SVG |
  | `hero-`   | [Heroicons](https://heroicons.com)      | CSS `<span>` |

  ## Heroicons styles

  | Suffix   | Style   |
  |----------|---------|
  | *(none)* | Outline |
  | `-solid` | Solid   |
  | `-mini`  | Mini    |

  Heroicons are embedded into `app.css` by the Tailwind plugin — no extra
  HTTP request. Lucide icons are read from the `lucide` dep at compile time.

  ## Examples

      <.icon name="lucide-x" />
      <.icon name="lucide-refresh-cw" class="w-4 h-4 animate-spin" />
      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """

  use StashixUi, :component

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "lucide-" <> icon_name} = assigns) do
    assigns = assign(assigns, :svg, read_icon(icon_name))

    ~H"""
    <svg
      :if={@svg}
      class={["inline-block align-middle", @class]}
      aria-hidden="true"
      xmlns="http://www.w3.org/2000/svg"
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      {@svg}
    </svg>
    """
  end

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]}></span>
    """
  end

  @icons_dir Path.expand("../../deps/lucide/icons", __DIR__)

  defp read_icon(name) do
    path = Path.join(@icons_dir, "#{name}.svg")

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.replace(~r/<svg[^>]*>/, "")
        |> String.replace("</svg>", "")
        |> String.trim()
        |> Phoenix.HTML.raw()

      _ ->
        nil
    end
  end
end
