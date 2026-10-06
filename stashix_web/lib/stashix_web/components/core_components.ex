defmodule StashixWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as modals, tables, and
  forms. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by `StashixWeb.UI.Icon`. See its docs for usage.
  """
  use Phoenix.Component
  use Gettext, backend: StashixWeb.Gettext

  import StashixWeb.UI.Icon
  import StashixWeb.UI.Dialog, only: [dialog: 1, dialog_footer: 1]
  import StashixWeb.UI.Ink, only: [ink_button: 1, pill: 1, sticker: 1, progress_bar: 1]
  import StashixWeb.UI.Menu, only: [ink_menu: 1, ink_select: 1, menu_item: 1, menu_separator: 1]

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss, :boolean, default: false, doc: "clear itself after a few seconds"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      phx-mounted={@auto_dismiss && JS.dispatch("stashix:flash-shown")}
      role="alert"
      class={[
        "flash-caption relative w-80 sm:w-96 max-w-full pl-4 pr-10 py-3 cursor-pointer pointer-events-auto",
        @kind == :info && "flash-caption-info bg-ink text-zinc-950",
        @kind == :error && "flash-caption-error bg-red-600 text-white"
      ]}
      {@rest}
    >
      <p :if={@title} class="font-display font-black uppercase text-xl leading-none tracking-wide">{@title}</p>
      <p class="mt-1 text-sm font-semibold leading-5">{msg}</p>
      <button
        type="button"
        class="absolute top-1.5 right-1.5 p-1.5 rounded-sm opacity-60 hover:opacity-100 hover:bg-black/15 transition"
        aria-label={gettext("close")}
      >
        <.icon name="lucide-x" class="h-4 w-4" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-5 right-5 left-5 sm:left-auto z-50 flex flex-col items-end gap-5 pointer-events-none">
      <.flash kind={:info} title={gettext("Success!")} flash={@flash} auto_dismiss />
      <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error")}
        phx-connected={hide("#client-error")}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="lucide-loader-circle" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error")}
        phx-connected={hide("#server-error")}
        hidden
      >
        {gettext("Hang in there while we get back on track")}
        <.icon name="lucide-loader-circle" class="ml-1 h-3 w-3 animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the data structure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-10 space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class="mt-2 flex items-center justify-between gap-6">
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               range search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField, doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global, include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="mt-2 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600">
      <.icon name="lucide-circle-alert" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">{col[:label]}</th>
            <th :if={@action != []} class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="lucide-arrow-left" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a dark-themed confirmation dialog driven by server state.

  Pass a `confirm` map with keys `:title`, `:message`, `:event`, and optionally
  `:params` (map of extra phx-value bindings). When non-nil the dialog is shown.
  The host LiveView must handle `"confirm_action"` and `"cancel_confirm"` events.

  ## Example

      <.confirm_dialog confirm={@pending_confirm} />
  """
  attr :confirm, :map, default: nil

  def confirm_dialog(assigns) do
    ~H"""
    <.dialog
      :if={@confirm}
      id="confirm-dialog"
      size="sm"
      title={@confirm.title}
      on_close={JS.push("cancel_confirm")}
    >
      <p class="text-sm text-gray-300">{@confirm.message}</p>
      <.dialog_footer>
        <.ink_button type="button" variant="ghost" size="md" phx-click="cancel_confirm">Cancel</.ink_button>
        <.ink_button type="button" variant="danger" size="md" phx-click="confirm_action">
          {@confirm[:confirm_label] || "Confirm"}
        </.ink_button>
      </.dialog_footer>
    </.dialog>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(StashixWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(StashixWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :alt, :string, default: ""
  attr :blurhash, :string, default: nil
  attr :class, :string, default: "w-full h-full object-cover block"
  attr :onerror, :string, default: nil

  def blurhash_image(assigns) do
    ~H"""
    <canvas
      :if={@blurhash}
      id={"bh-#{@id}"}
      width="32"
      height="48"
      class="absolute inset-0 w-full h-full"
      style="filter:blur(6px);transform:scale(1.05)"
    ></canvas>
    <img
      id={@id}
      phx-hook="CoverImage"
      src={@src}
      alt={@alt}
      class={@class}
      data-blurhash={@blurhash}
      data-canvas-id={"bh-#{@id}"}
      onerror={@onerror}
    />
    """
  end

  @doc """
  Cover card for a book or a series: the cover with its marks, title and
  subtitle underneath.

    * `badge` — ink sticker in the bottom-left corner (issue number, issue count)
    * `page_count` — small page tally in the bottom-right corner (books only)
    * `progress` — fraction read; draws a bar along the bottom edge and, at 1.0,
      the read mark
    * `read_mark` — `check` (a small ink tick) or `stamp` (a tilted READ stamp)
    * `type` — `:book` or `:series`, picks the placeholder icon
    * `stack` — more covers of the same series; they slide out from behind on
      hover and are only fetched then
  """
  attr :navigate, :any, required: true
  attr :title, :string, required: true
  attr :cover_url, :string, default: nil
  attr :size, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :badge, :string, default: nil
  attr :progress, :float, default: nil
  attr :read_mark, :string, default: "check", values: ~w(check stamp)
  attr :type, :atom, default: :book
  attr :page_count, :integer, default: nil
  attr :blurhash, :string, default: nil
  attr :stack, :list, default: [], doc: "up to two more cover URLs, fanned out behind the cover on hover"
  attr :class, :string, default: ""

  def media_card(assigns) do
    assigns =
      assigns
      |> assign(
        :img_src,
        if(assigns.cover_url && assigns.size,
          do: "#{assigns.cover_url}?s=#{assigns.size}",
          else: assigns.cover_url
        )
      )
      |> assign(:cover_id, "cover-#{:erlang.phash2(assigns.navigate)}")
      |> assign(:read, is_number(assigns.progress) and assigns.progress >= 1.0)
      |> assign(:fallback_icon, if(assigns.type == :series, do: "lucide-book-copy", else: "lucide-book-open"))

    ~H"""
    <.link navigate={@navigate} class={["media-card group relative block min-w-0", @class]}>
      <div class="relative">
        <span
          :for={{url, depth} <- @stack |> Enum.take(2) |> Enum.with_index(1) |> Enum.reverse()}
          class="media-card-fan"
          data-depth={depth}
          style={"--src: url('#{url}')"}
          aria-hidden="true"
        ></span>
        <div class="media-card-cover relative aspect-[2/3] rounded-md overflow-hidden bg-gray-800 ring-1 ring-white/10">
          <%= if @img_src do %>
            <.blurhash_image
              id={@cover_id}
              src={@img_src}
              alt={@title}
              blurhash={@blurhash}
              class="w-full h-full object-cover"
              onerror="this.style.display='none';this.nextElementSibling.style.display='flex'"
            />
            <div class="w-full h-full hidden items-center justify-center text-gray-600">
              <.icon name={@fallback_icon} class="w-8 h-8" />
            </div>
          <% else %>
            <div class="w-full h-full flex items-center justify-center text-gray-600">
              <.icon name={@fallback_icon} class="w-8 h-8" />
            </div>
          <% end %>

          <div
            :if={@read && @read_mark == "stamp"}
            class="absolute inset-0 bg-gray-950/45 pointer-events-none"
            aria-hidden="true"
          >
          </div>
          <div class="absolute inset-x-0 bottom-0 h-14 bg-gradient-to-t from-gray-950/85 to-transparent pointer-events-none">
          </div>

          <.sticker :if={@badge} size="xs" tilt={false} class="absolute bottom-2 left-2 max-w-[calc(100%-1rem)] truncate">
            {@badge}
          </.sticker>
          <span
            :if={@type == :book && @page_count && @page_count > 0}
            class={[
              "absolute right-2 flex items-center gap-0.5 px-1 rounded-sm bg-gray-950/70 text-[10px] font-semibold text-gray-200 tabular-nums",
              if(@badge, do: "top-2", else: "bottom-2")
            ]}
            title={"#{@page_count} pages"}
          >
            <.icon name="lucide-sticky-note" class="w-2.5 h-2.5 shrink-0" />
            {@page_count}
          </span>

          <span
            :if={@read && @read_mark == "check"}
            class="absolute top-2 left-2 flex items-center justify-center w-5 h-5 rounded-sm bg-ink text-zinc-950 shadow-[2px_2px_0_0_rgb(0_0_0/0.6)]"
            title="Read"
          >
            <.icon name="lucide-check" class="w-3.5 h-3.5 stroke-[3]" />
            <span class="sr-only">Read</span>
          </span>
          <span
            :if={@read && @read_mark == "stamp"}
            class="read-stamp absolute top-[14%] left-1/2 px-2 pt-0.5 border-[3px] border-ink rounded-sm bg-gray-950/60 text-ink font-display font-black uppercase text-xl leading-none"
          >
            Read
          </span>

          <.progress_bar
            :if={@progress}
            value={@progress}
            rounded={false}
            track="bg-gray-950/70"
            class="absolute bottom-0 inset-x-0 h-1"
          />
        </div>
      </div>
      <div class="pt-2 px-0.5">
        <p class="text-[13px] leading-snug font-semibold text-gray-200 group-hover:text-white transition-colors line-clamp-2">
          {@title}
        </p>
        <p :if={@subtitle} class="mt-0.5 text-xs text-gray-500 tabular-nums">{@subtitle}</p>
      </div>
    </.link>
    """
  end

  @doc "`media_card/1` for a series: years, issue count and the fanned stack of its next covers."
  attr :series, :map, required: true
  attr :size, :string, default: "m"
  attr :class, :string, default: ""

  def series_card(assigns) do
    ~H"""
    <.media_card
      navigate={"/series/#{@series.id}"}
      title={@series.name}
      cover_url={"/api/series/#{@series.id}/cover"}
      size={@size}
      subtitle={Stashix.Formatters.series_years(@series)}
      badge={@series.issue_count && "#{@series.issue_count} #{if @series.issue_count == 1, do: "issue", else: "issues"}"}
      type={:series}
      blurhash={@series.cover_blurhash}
      stack={Enum.map(Map.get(@series, :stack_book_ids) || [], &"/api/books/#{&1}/cover?s=s")}
      class={@class}
    />
    """
  end

  @doc """
  `media_card/1` for a book. `as={:issue}` puts the issue number in the title
  and on a sticker and names the series underneath; the default shows the
  year and the page count. `read` is the number of pages read so far.
  """
  attr :book, :map, required: true
  attr :as, :atom, default: :book, values: [:book, :issue]
  attr :read, :integer, default: nil
  attr :size, :string, default: "m"
  attr :class, :string, default: ""

  def book_card(assigns) do
    book = assigns.book
    issue? = assigns.as == :issue
    series = if issue? and Ecto.assoc_loaded?(book.series), do: book.series
    year = book.year && to_string(book.year)

    assigns =
      assign(assigns,
        title: if(issue? and book.issue_number, do: "##{book.issue_number} – #{book.title}", else: book.title),
        subtitle: (series && series.name) || year,
        badge:
          cond do
            !issue? or is_nil(book.issue_number) -> nil
            book.volume -> "Vol #{book.volume} ##{book.issue_number}"
            true -> "##{book.issue_number}"
          end,
        progress:
          if(assigns.read && book.page_count && book.page_count > 1,
            do: assigns.read / (book.page_count - 1)
          ),
        blurhash: Ecto.assoc_loaded?(book.cover) && book.cover && book.cover.blurhash
      )

    ~H"""
    <.media_card
      navigate={"/book/#{@book.id}"}
      title={@title}
      cover_url={"/api/books/#{@book.id}/cover"}
      size={@size}
      subtitle={@subtitle}
      badge={@badge}
      progress={@progress}
      page_count={if @as == :book, do: @book.page_count}
      type={:book}
      blurhash={@blurhash || nil}
      class={@class}
    />
    """
  end

  @doc "Admin ⋮ menu for a library: scan, force rescan, settings. Events are handled by `StashixWeb.Live.Hooks`."
  attr :id, :string, required: true
  attr :library_id, :string, required: true
  attr :class, :any, default: nil

  def library_menu(assigns) do
    ~H"""
    <.ink_menu id={@id} class={@class}>
      <:trigger
        label="Library actions"
        class="p-1.5 rounded text-gray-500 hover:text-white hover:bg-white/10 transition-colors"
      >
        <.icon name="lucide-ellipsis-vertical" class="w-3.5 h-3.5" />
      </:trigger>
      <.menu_item icon="lucide-refresh-cw" phx-click={JS.push("sidebar_scan", value: %{id: @library_id})}>
        Scan for new files
      </.menu_item>
      <.menu_item icon="lucide-rotate-ccw" phx-click={JS.push("sidebar_force_scan", value: %{id: @library_id})}>
        Force rescan
      </.menu_item>
      <.menu_separator />
      <.menu_item icon="lucide-settings" navigate="/admin/libraries">Settings</.menu_item>
    </.ink_menu>
    """
  end

  # ---------------------------------------------------------------------------
  # Browse / list-page shared components
  # ---------------------------------------------------------------------------

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :controls

  def browse_header(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-white">{@title}</h1>
        <p :if={@subtitle} class="text-sm text-gray-500 mt-0.5">{@subtitle}</p>
      </div>
      <div :if={@controls != []} class="flex flex-wrap items-center gap-2">
        {render_slot(@controls)}
      </div>
    </div>
    """
  end

  @doc """
  Control row above a browse grid: library filter pills on the left (only
  with more than one library to pick from), sort on the right.
  """
  attr :libraries, :list, default: []
  attr :library_id, :string, default: nil
  attr :sort_options, :list, required: true
  attr :sort, :string, required: true

  def browse_toolbar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-x-4 gap-y-3 pb-4 border-b border-white/15">
      <div class="flex flex-wrap items-center gap-1.5">
        <.library_filter :if={length(@libraries) > 1} libraries={@libraries} selected_id={@library_id} />
      </div>
      <.sort_select options={@sort_options} selected={@sort} class="ml-auto" />
    </div>
    """
  end

  attr :libraries, :list, required: true
  attr :selected_id, :string, default: nil
  attr :event, :string, default: "filter_library"

  def library_filter(assigns) do
    ~H"""
    <.pill tag="button" type="button" active={is_nil(@selected_id)} phx-click={@event} phx-value-id="">
      All libraries
    </.pill>
    <.pill
      :for={lib <- @libraries}
      tag="button"
      type="button"
      active={@selected_id == lib.id}
      phx-click={@event}
      phx-value-id={lib.id}
    >
      {lib.name}
    </.pill>
    """
  end

  attr :id, :string, default: "sort-select"
  attr :options, :list, required: true
  attr :selected, :string, required: true
  attr :event, :string, default: "sort"
  attr :class, :string, default: nil

  def sort_select(assigns) do
    ~H"""
    <form id={@id} phx-change={@event} class={@class}>
      <.ink_select id={"#{@id}-input"} name="value" label="Sort" value={@selected} options={@options} />
    </form>
    """
  end

  attr :id, :string, default: nil
  slot :inner_block, required: true

  def media_grid(assigns) do
    ~H"""
    <div
      id={@id}
      class="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8 xl:grid-cols-8 gap-4"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true

  def browse_empty(assigns) do
    ~H"""
    <div class="text-center py-16 text-gray-500">
      <.icon name={@icon} class="w-12 h-12 mx-auto mb-3 text-gray-700" />
      <p>{@label}</p>
    </div>
    """
  end

  # ---------------------------------------------------------------------------

  attr :id, :string, default: nil
  attr :page, :integer, required: true
  attr :total_pages, :integer, required: true
  attr :on_page, :string, default: "goto_page"
  attr :scroll_to, :string, default: nil

  def pagination(assigns) do
    assigns = assign(assigns, :pages, pagination_pages(assigns.page, assigns.total_pages))

    ~H"""
    <nav :if={@total_pages > 1} id={@id} aria-label="Pages" class="flex items-center justify-center gap-1">
      <.page_step
        icon="lucide-chevron-first"
        label="First page"
        disabled={@page == 1}
        click={page_click(@on_page, 1, @scroll_to)}
      />
      <.page_step
        icon="lucide-chevron-left"
        label="Previous page"
        disabled={@page == 1}
        click={page_click(@on_page, @page - 1, @scroll_to)}
      />

      <button
        :for={{p, i} <- Enum.with_index(@pages, 1)}
        type="button"
        phx-click={page_click(@on_page, p, @scroll_to)}
        aria-label={"Page #{p}"}
        aria-current={p == @page && "page"}
        class={[
          "h-9 min-w-9 px-1.5 items-center justify-center rounded-sm font-display font-black text-xl leading-none tabular-nums transition-colors",
          if(i > 5 and p != @page, do: "hidden sm:flex", else: "flex"),
          if(p == @page,
            do: "sticker bg-ink text-zinc-950",
            else: "text-gray-400 hover:text-white hover:bg-white/10"
          )
        ]}
      >
        {p}
      </button>

      <.page_step
        icon="lucide-chevron-right"
        label="Next page"
        disabled={@page == @total_pages}
        click={page_click(@on_page, @page + 1, @scroll_to)}
      />
      <.page_step
        icon="lucide-chevron-last"
        label="Last page"
        disabled={@page == @total_pages}
        click={page_click(@on_page, @total_pages, @scroll_to)}
      />
    </nav>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :disabled, :boolean, required: true
  attr :click, JS, required: true

  defp page_step(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@click}
      disabled={@disabled}
      aria-label={@label}
      class="flex items-center justify-center w-9 h-9 rounded-sm text-gray-400 hover:text-white hover:bg-white/10 disabled:opacity-25 disabled:pointer-events-none transition-colors"
    >
      <.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  defp page_click(event, page, nil), do: JS.push(event, value: %{"page" => to_string(page)})

  defp page_click(event, page, scroll_to) do
    JS.push(event, value: %{"page" => to_string(page)})
    |> JS.dispatch("stashix:scroll-to", detail: %{id: scroll_to})
  end

  defp pagination_pages(_current, total) when total <= 11, do: Enum.to_list(1..total)

  defp pagination_pages(current, total) do
    half = 5
    start = max(1, min(current - half, total - 10))
    finish = min(total, start + 10)
    Enum.to_list(start..finish)
  end
end
