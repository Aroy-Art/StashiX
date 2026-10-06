// InkMenu: the behaviour behind <.ink_menu> and <.ink_select>.
//
// The panel is a manual popover, so it sits in the browser's top layer (no
// portal, nothing can clip it) while staying where it is in the DOM, which
// keeps phx-click and LiveView patches working. Everything the server does not
// know about (open state, position, focus, the filter box) lives here and is
// re-applied in updated(), because a patch resets attributes it did not render.
//
// Expected markup inside the hook element:
//   [data-menu-trigger]   the button that opens the panel
//   [data-menu-panel]     the popover; data-align="start|end"
//   [data-menu-item]      focusable rows; data-keep-open leaves the menu open
// Select mode (data-select on the hook element) adds:
//   input[data-select-input]   hidden input carrying the value
//   [data-select-label]        text of the current option, inside the trigger
//   [data-menu-item][data-value][data-label]   one per option
//   input[data-menu-filter]    optional box that narrows the options

const GAP = 8
const EDGE = 8

const InkMenu = {
  mounted() {
    this.open = false
    this.trigger = this.el.querySelector("[data-menu-trigger]")
    this.panel = this.el.querySelector("[data-menu-panel]")
    this.isSelect = this.el.hasAttribute("data-select")
    if (this.isSelect) {
      this.serverValue = this.el.dataset.value
      this.value = this.serverValue
    }

    this.onTriggerClick = (e) => {
      e.preventDefault()
      this.toggle()
    }
    this.onTriggerKeydown = (e) => {
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault()
        this.show(e.key === "ArrowUp" ? "last" : "first")
      }
    }
    this.onPanelClick = (e) => {
      const item = e.target.closest("[data-menu-item]")
      if (!item || !this.panel.contains(item) || item.disabled) return
      if (this.isSelect) this.pick(item)
      if (!item.hasAttribute("data-keep-open")) this.hide({ focusTrigger: true })
    }
    this.onPanelKeydown = (e) => this.handleKey(e)
    this.onFilterInput = () => this.applyFilter()
    // Capture phase: runs before anything under the pointer hears about it.
    this.onOutsidePointer = (e) => {
      if (!this.open || this.el.contains(e.target)) return
      this.hide()
      // A modal menu eats the click that dismisses it, so it does not also
      // land on whatever is underneath (the reader turns pages on tap).
      if (this.el.hasAttribute("data-modal")) this.swallow(e)
    }
    // Scrolling the panel's own list must not re-measure it.
    this.onReposition = (e) => {
      if (this.open && !(e.target instanceof Node && this.panel.contains(e.target))) this.place()
    }
    this.onOtherMenu = (e) => e.detail !== this && this.hide()

    this.trigger.addEventListener("click", this.onTriggerClick)
    this.trigger.addEventListener("keydown", this.onTriggerKeydown)
    this.panel.addEventListener("click", this.onPanelClick)
    this.panel.addEventListener("keydown", this.onPanelKeydown)
    this.panel.addEventListener("input", this.onFilterInput)
    document.addEventListener("pointerdown", this.onOutsidePointer, true)
    window.addEventListener("resize", this.onReposition)
    window.addEventListener("scroll", this.onReposition, true)
    window.addEventListener("ink-menu:opened", this.onOtherMenu)

    this.sync()
  },

  updated() {
    if (this.isSelect && this.el.dataset.value !== this.serverValue) {
      // The server changed the value (form recovery, "clear filters"): it wins.
      this.serverValue = this.el.dataset.value
      this.value = this.serverValue
    }
    // A patch drops the popover out of the top layer if it re-renders the
    // panel element, so put it back before re-applying everything else.
    if (this.open && !this.panel.matches(":popover-open")) this.panel.showPopover()
    this.sync()
  },

  destroyed() {
    document.removeEventListener("pointerdown", this.onOutsidePointer, true)
    window.removeEventListener("resize", this.onReposition)
    window.removeEventListener("scroll", this.onReposition, true)
    window.removeEventListener("ink-menu:opened", this.onOtherMenu)
  },

  // Re-apply client-side state after mount or a patch.
  sync() {
    this.trigger.setAttribute("aria-expanded", String(this.open))
    this.el.toggleAttribute("data-open", this.open)
    if (this.isSelect) this.reflectValue()
    if (this.open) {
      this.applyFilter()
      this.place()
    }
  },

  toggle() {
    this.open ? this.hide({ focusTrigger: true }) : this.show()
  },

  show(focus = "current") {
    if (this.open) return
    this.open = true
    window.dispatchEvent(new CustomEvent("ink-menu:opened", { detail: this }))
    this.panel.showPopover()
    const filter = this.filterBox()
    if (filter) filter.value = ""
    this.sync()

    const items = this.items()
    const current = items.find((i) => i.classList.contains("is-active"))
    if (current) current.scrollIntoView({ block: "nearest" })
    if (filter) return filter.focus()
    const target = focus === "last" ? items[items.length - 1] : (focus === "current" && current) || items[0]
    if (target) target.focus()
    else this.panel.focus()
  },

  hide({ focusTrigger = false } = {}) {
    if (!this.open) return
    this.open = false
    if (this.panel.matches(":popover-open")) this.panel.hidePopover()
    this.sync()
    if (focusTrigger) this.trigger.focus()
  },

  // Below the trigger, flipped above when there is no room; kept on screen.
  place() {
    const t = this.trigger.getBoundingClientRect()
    const p = this.panel
    p.style.maxHeight = ""
    const width = p.offsetWidth
    const height = p.offsetHeight
    const vw = document.documentElement.clientWidth
    const vh = window.innerHeight

    let left = p.dataset.align === "start" ? t.left : t.right - width
    left = Math.max(EDGE, Math.min(left, vw - width - EDGE))

    const below = vh - t.bottom - GAP - EDGE
    const above = t.top - GAP - EDGE
    let top
    if (height <= below || below >= above) {
      top = t.bottom + GAP
      if (height > below) p.style.maxHeight = `${Math.max(below, 96)}px`
    } else {
      const h = Math.min(height, above)
      if (height > above) p.style.maxHeight = `${above}px`
      top = t.top - GAP - h
    }

    p.style.left = `${Math.round(left)}px`
    p.style.top = `${Math.round(top)}px`
    if (p.hasAttribute("data-match-width")) p.style.minWidth = `${Math.round(t.width)}px`
  },

  items() {
    return Array.from(this.panel.querySelectorAll("[data-menu-item]")).filter(
      (i) => !i.disabled && !i.hidden && i.getClientRects().length > 0
    )
  },

  filterBox() {
    return this.panel.querySelector("[data-menu-filter]")
  },

  handleKey(e) {
    const filter = this.filterBox()
    const inFilter = filter && e.target === filter
    const items = this.items()
    const index = items.indexOf(document.activeElement)
    const focus = (i) => items.length && items[(i + items.length) % items.length].focus()

    switch (e.key) {
      case "Escape":
        e.preventDefault()
        this.hide({ focusTrigger: true })
        break
      case "Tab":
        this.hide()
        return
      case "ArrowDown":
        e.preventDefault()
        focus(index + 1)
        break
      case "ArrowUp":
        e.preventDefault()
        if (filter && index <= 0) filter.focus()
        else focus(index - 1)
        break
      case "Home":
        if (inFilter) return
        e.preventDefault()
        focus(0)
        break
      case "End":
        if (inFilter) return
        e.preventDefault()
        focus(items.length - 1)
        break
      case "Enter":
        if (!inFilter) return
        // Never submit the surrounding form from the filter box.
        e.preventDefault()
        if (items[0]) items[0].click()
        break
      default:
        if (inFilter || e.key.length !== 1 || e.ctrlKey || e.metaKey || e.altKey) return
        this.typeAhead(e.key, items, index)
    }
    // The menu owns its keys while open; pages bind arrows and letters too.
    e.stopPropagation()
  },

  typeAhead(key, items, index) {
    const wanted = key.toLowerCase()
    const after = items.slice(index + 1).concat(items.slice(0, index + 1))
    const match = after.find((i) => (i.dataset.label || i.textContent).trim().toLowerCase().startsWith(wanted))
    if (match) match.focus()
  },

  applyFilter() {
    const filter = this.filterBox()
    if (!filter) return
    const q = filter.value.trim().toLowerCase()
    let shown = 0
    this.panel.querySelectorAll("[data-menu-item]").forEach((item) => {
      const hit = q === "" || (item.dataset.label || item.textContent).toLowerCase().includes(q)
      item.hidden = !hit
      if (hit) shown++
    })
    const empty = this.panel.querySelector("[data-menu-empty]")
    if (empty) empty.hidden = shown > 0
  },

  // --- select mode ---------------------------------------------------------

  pick(item) {
    const input = this.el.querySelector("[data-select-input]")
    const changed = this.value !== item.dataset.value
    this.value = item.dataset.value
    this.reflectValue()
    if (changed) {
      input.dispatchEvent(new Event("input", { bubbles: true }))
      input.dispatchEvent(new Event("change", { bubbles: true }))
    }
  },

  reflectValue() {
    const input = this.el.querySelector("[data-select-input]")
    if (input.value !== this.value) input.value = this.value
    let label = null
    this.panel.querySelectorAll("[data-menu-item]").forEach((item) => {
      const active = item.dataset.value === this.value
      item.classList.toggle("is-active", active)
      item.setAttribute("aria-selected", String(active))
      if (active) label = item.dataset.label
    })
    const slot = this.trigger.querySelector("[data-select-label]")
    if (slot && label !== null) slot.textContent = label
    // Only a select with a prompt has an "unset" state worth marking.
    this.el.toggleAttribute("data-has-value", this.el.hasAttribute("data-clearable") && this.value !== "")
  },

  // Stop this press from reaching anything else, including the click it ends in.
  swallow(e) {
    e.preventDefault()
    e.stopPropagation()
    const stop = (ev) => {
      ev.preventDefault()
      ev.stopPropagation()
    }
    const events = ["pointerup", "mousedown", "mouseup", "touchend", "click"]
    const release = () => events.forEach((name) => document.removeEventListener(name, stop, true))
    events.forEach((name) => document.addEventListener(name, stop, true))
    // The click is the last event of the press; the timeout covers a drag that never clicks.
    document.addEventListener("click", () => setTimeout(release), { capture: true, once: true })
    setTimeout(release, 1500)
  },
}

export default InkMenu
