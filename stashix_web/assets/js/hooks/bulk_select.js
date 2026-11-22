/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// BulkSelect: pick several cards on a page to add them to a collection.
//
// Lives on StashixWeb.BulkSelect (once, in the app layout). A toolbar's
// Select button dispatches "bulk:toggle" here. While on, <html data-bulk>
// shows a tick box on every card that can be picked ([data-select-id],
// [data-select-type]) and a click on one ticks it instead of opening it;
// shift-click ticks the range from the last one, Esc leaves. Picks survive
// page patches (paging, sorting) and are reported to the component as
// "selection"; it pushes "bulk:clear" once they are added.

const key = (el) => `${el.dataset.selectType}:${el.dataset.selectId}`

const BulkSelect = {
  mounted() {
    this.on = false
    this.picked = new Map()
    this.last = null

    this.el.addEventListener("bulk:toggle", () => this.setMode(!this.on))
    this.el.addEventListener("bulk:clear", () => this.clear())
    this.handleEvent("bulk:clear", () => this.clear(false))

    // Window, capture phase: before LiveView's link handling sees the click.
    this.onClick = (e) => {
      if (!this.on || e.button !== 0) return
      const card = e.target.closest("[data-select-id][data-select-type]")
      if (!card || this.el.contains(card)) return
      e.preventDefault()
      e.stopImmediatePropagation()
      this.toggle(card, e.shiftKey)
    }
    this.onKey = (e) => {
      if (this.on && e.key === "Escape" && !document.querySelector("dialog[open], :popover-open")) this.setMode(false)
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
    document.querySelectorAll("[data-bulk-toggle]").forEach((b) => b.setAttribute("aria-pressed", String(on)))
    this.paint()
    this.pushEventTo(this.el, "mode", {on})
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
