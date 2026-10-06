defmodule StashixWeb.UI.Dialog do
  @moduledoc """
  Modal dialog of the "ink" design language, on the native `<dialog>` element.

  The browser supplies the focus trap, the backdrop and Escape handling; the
  `InkDialog` hook (`assets/js/hooks/ink_dialog.js`) only opens it and reports
  close requests. Specimens live at `/dev/ui`.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import StashixWeb.UI.Ink, only: [display_heading: 1, icon_button: 1]

  @doc """
  Render it to open it; stop rendering it to close it:

      <.dialog :if={@editing} id="edit" title="Edit" on_close={JS.push("close_edit")}>
        …
      </.dialog>

  `on_close` runs when the user asks to close (Escape, the ✕, a click on the
  backdrop). The dialog stays up until the server stops rendering it, so an
  `on_close` that does nothing makes a dialog that cannot be dismissed.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, JS, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg xl)
  attr :class, :any, default: nil
  slot :description
  slot :inner_block, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      phx-hook="InkDialog"
      phx-mounted={JS.ignore_attributes(["open"])}
      data-on-close={@on_close}
      aria-labelledby={"#{@id}-title"}
      aria-describedby={@description != [] && "#{@id}-description"}
      class={["ink-dialog", dialog_size(@size), @class]}
    >
      <div class="ink-dialog-panel">
        <header class="flex items-start gap-4 px-5 sm:px-6 pt-5 pb-4 border-b border-white/10">
          <div class="flex-1 min-w-0">
            <.display_heading id={"#{@id}-title"} size="panel">{@title}</.display_heading>
            <div :if={@description != []} id={"#{@id}-description"} class="mt-2 text-sm text-gray-400">
              {render_slot(@description)}
            </div>
          </div>
          <.icon_button icon="lucide-x" label="Close" data-dialog-close />
        </header>
        <div class="px-5 sm:px-6 py-5">
          {render_slot(@inner_block)}
        </div>
      </div>
    </dialog>
    """
  end

  defp dialog_size("sm"), do: "max-w-sm"
  defp dialog_size("md"), do: "max-w-xl"
  defp dialog_size("lg"), do: "max-w-3xl"
  defp dialog_size("xl"), do: "max-w-5xl"

  @doc "Right-aligned row of buttons at the foot of a dialog; put it inside the form it submits."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def dialog_footer(assigns) do
    ~H"""
    <div class={["flex flex-col-reverse sm:flex-row sm:justify-end gap-3 pt-4", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
