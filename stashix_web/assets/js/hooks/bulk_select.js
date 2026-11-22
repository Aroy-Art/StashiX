/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// BulkSelect: pick several cards on a page to add them to a collection.
//
// Lives on StashixWeb.BulkSelect (once, in the app layout). "Select
// multiple" in a card's menu dispatches "bulk:start" here, turning the mode
// on with that card picked; the bar's Done sends "bulk:toggle" to leave.
// While on, <html data-bulk>
// shows the tick box (an ink <.checkbox>) on every card that can be picked
// ([data-select-id], [data-select-type]) and a click on one ticks it
// instead of opening it;
// shift-click ticks the range from the last one, Esc leaves. Picks survive
// page patches (paging, sorting) and are reported to the component as
// "selection"; it pushes "bulk:clear" once they are added.
// "bulk:download" posts the picks to /api/download for one ZIP.

const key = (el) => `${el.dataset.selectType}:${el.dataset.selectId}`

const BulkSelect = {
  mounted() {
    this.on = false
    this.picked = new Map()
    this.last = null

    this.el.addEventListener("bulk:toggle", () => this.setMode(!this.on))
    this.el.addEventListener("bulk:clear", () => this.clear())
    this.el.addEventListener("bulk:start", (e) => this.start(e.detail))
    this.el.addEventListener("bulk:download", () => this.download())
    this.handleEvent("bulk:clear", () => this.clear(false))

    // Window, capture phase: before LiveView's link handling sees the click.
    this.onClick = (e) => {
      if (!this.on || e.button !== 0 || document.documentElement.hasAttribute("data-card-menu")) return
      const card = e.target.closest("[data-select-id][data-select-type]")
      if (!card || this.el.contains(card)) return
      e.preventDefault()
      e.stopImmediatePropagation()
      this.toggle(card, e.shiftKey)
    }
    this.onKey = (e) => {
      if (
        this.on &&
        e.key === "Escape" &&
        !document.querySelector("dialog[open], :popover-open") &&
        !document.documentElement.hasAttribute("data-card-menu")
      )
        this.setMode(false)
    }
    window.addEventListener("click", this.onClick, true)
    window.addEventListener("keydown", this.onKey)

    // Cards come and go with patches: keep their ticks right.
    this.observer = new MutationObserver(() => this.on && this.paint())
    this.observer.observe(document.body, {childList: true, subtree: true})

    // A new page starts with the mode off.
    this.onNavigate = () => this.on && this.setMode(false)
    window.addEventListener("phx:navigate", this.onNavigate)
  },

  destroyed() {
    window.removeEventListener("click", this.onClick, true)
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("phx:navigate", this.onNavigate)
    this.observer.disconnect()
    document.documentElement.removeAttribute("data-bulk")
  },

  setMode(on) {
    this.on = on
    this.picked.clear()
    this.last = null
    document.documentElement.toggleAttribute("data-bulk", on)
    this.paint()
    this.pushEventTo(this.el, "mode", {on})
  },

  start({type, id}) {
    if (!this.on) this.setMode(true)
    const card = this.cards().find((c) => c.dataset.selectType === type && c.dataset.selectId === id)
    this.picked.set(`${type}:${id}`, {selectType: type, selectId: id})
    if (card) this.last = card
    this.paint()
    this.report()
  },

  download() {
    if (this.picked.size === 0) return
    const form = document.createElement("form")
    form.method = "post"
    form.action = "/api/download"
    form.hidden = true
    const field = (name, value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }
    field("_csrf_token", document.querySelector("meta[name='csrf-token']")?.content || "")
    this.picked.forEach((d) => field("items[]", `${d.selectType}:${d.selectId}`))
    document.body.appendChild(form)
    form.submit()
    form.remove()
  },

  clear(report = true) {
    this.picked.clear()
    this.last = null
    this.paint()
    if (report) this.report()
  },

  cards() {
    return Array.from(document.querySelectorAll("[data-select-id][data-select-type]")).filter(
      (c) => !this.el.contains(c)
    )
  },

  toggle(card, range) {
    const cards = this.cards()
    if (range && this.last && cards.includes(this.last)) {
      const [a, b] = [cards.indexOf(this.last), cards.indexOf(card)].sort((x, y) => x - y)
      cards.slice(a, b + 1).forEach((c) => this.picked.set(key(c), c.dataset))
    } else if (this.picked.has(key(card))) {
      this.picked.delete(key(card))
    } else {
      this.picked.set(key(card), card.dataset)
    }
    this.last = card
    this.paint()
    this.report()
  },

  paint() {
    this.cards().forEach((c) => {
      const on = this.on && this.picked.has(key(c))
      if (c.hasAttribute("data-picked") !== on) c.toggleAttribute("data-picked", on)
      const tick = c.querySelector(".media-card-tick input[type=checkbox]")
      if (tick && tick.checked !== on) tick.checked = on
      if (this.on) c.setAttribute("aria-pressed", String(on))
      else c.removeAttribute("aria-pressed")
    })
  },

  report() {
    const items = Array.from(this.picked.values(), (d) => ({type: d.selectType, id: d.selectId}))
    this.pushEventTo(this.el, "selection", {items})
  },
}

export default BulkSelect
