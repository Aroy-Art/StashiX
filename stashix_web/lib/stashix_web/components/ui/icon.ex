defmodule StashixWeb.UI.Icon do
  @moduledoc """
  Renders [Lucide](https://lucide.dev) icons as inline SVG.

      <.icon name="lucide-x" />
      <.icon name="lucide-refresh-cw" class="w-4 h-4 animate-spin" />

  Icon bodies are read from the `lucide` dep when this module compiles. An
  unknown name renders nothing and logs a warning; a test checks every name
  used in the web layer against the set.
  """

  use Phoenix.Component

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

  # Every Lucide icon body is read once, at compile time, into a map. Rendering
  # an icon is then a map lookup instead of a file read, and a release does not
  # need the `deps/` directory at runtime.
  @icons_dir Path.expand("../../../../deps/lucide/icons", __DIR__)
  @icon_files Path.wildcard(Path.join(@icons_dir, "*.svg"))
  @icon_listing_hash :erlang.md5(Enum.map(@icon_files, &Path.basename/1))

  for file <- @icon_files do
    @external_resource file
  end

  @icons Map.new(@icon_files, fn file ->
           body =
             file
             |> File.read!()
             |> String.replace(~r/<svg[^>]*>/, "")
             |> String.replace("</svg>", "")
             |> String.trim()

           {Path.basename(file, ".svg"), {:safe, body}}
         end)

  @doc false
  # Recompile when the icon set gains or loses files (a dependency update).
  def __mix_recompile__? do
    @icons_dir |> Path.join("*.svg") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> :erlang.md5() !=
      @icon_listing_hash
  end

  @doc "True when the Lucide set has an icon of that name (without the `lucide-` prefix)."
  def lucide?(name), do: Map.has_key?(@icons, name)

  defp read_icon(name) do
    case @icons do
      %{^name => svg} ->
        svg

      _ ->
        require Logger
        Logger.warning("unknown icon lucide-#{name}; nothing is rendered for it")
        nil
    end
  end
end
