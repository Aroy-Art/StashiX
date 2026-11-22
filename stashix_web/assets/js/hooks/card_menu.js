/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// CardMenu: a long press or right click on a book or series card opens its
// menu (StashixWeb.CardMenu, once in the app layout).
//
// Cards are anything the bulk selection can pick ([data-select-id],
// [data-select-type]). A press held still for HOLD ms (any pointer), a
// right click, or the context menu key on a focused card asks the
// component to "open"; the click that ends a long press is swallowed so it
// doesn't also open the card. While the menu is open <html data-card-menu>
// is set (BulkSelect ignores clicks then). On wide screens the panel sits
// at the pointer, kept inside the window; on phones CSS makes it a sheet.
// Esc, a click outside, scrolling the page or choosing an item closes it.

const HOLD = 500
const SLOP = 10
const EDGE = 8

const CardMenu = {
  mounted() {
    this.key = null
    this.point = null
    this.timer = null
    this.opener = null

    this.onPointerDown = (e) => {
      if (e.button !== 0 || this.key) return
      const card = this.cardAt(e.target)
      if (!card) return
      this.start = {x: e.clientX, y: e.clientY}
      clearTimeout(this.timer)
      this.timer = setTimeout(() => {
        this.timer = null
        this.pressClick = true
        setTimeout(() => (this.pressClick = false), 1000)
        navigator.vibrate?.(10)
        this.open(card, this.start.x, this.start.y)
      }, HOLD)
    }
    this.onPointerMove = (e) => {
      if (this.timer && Math.hypot(e.clientX - this.start.x, e.clientY - this.start.y) > SLOP) this.cancelHold()
    }
    this.cancelHold = () => {
      clearTimeout(this.timer)
      this.timer = null
    }
    this.onContextMenu = (e) => {
      const card = this.cardAt(e.target)
      if (!card) return
      e.preventDefault()
      // Touch browsers send one at the end of their own long press.
      if (this.key === key(card)) return
      this.cancelHold()
      if (e.clientX === 0 && e.clientY === 0) {
        // From the keyboard: under the card's cover.
        const r = card.getBoundingClientRect()
        this.open(card, r.left + 12, r.top + Math.min(r.height, 120), true)
      } else {
        this.open(card, e.clientX, e.clientY)
      }
    }
    this.onKey = (e) => {
      if (this.key && e.key === "Escape" && !document.querySelector("dialog[open]")) {
        e.preventDefault()
        this.close(true)
      }
    }
    // Outside the panel: close, and don't let the click land underneath.
    // The click that ends a long press is swallowed too, but keeps it open.
    this.onOutside = (e) => {
      if (this.pressClick) {
        this.pressClick = false
        e.preventDefault()
        e.stopImmediatePropagation()
        return
      }
      if (!this.key || this.panel()?.contains(e.target) || e.target.closest?.("dialog")) return
      e.preventDefault()
      e.stopImmediatePropagation()
      this.close()
    }
    // A scroll still in flight when the menu opens doesn't count.
    this.onScroll = (e) => {
      if (!this.key || performance.now() - this.openedAt < 300 || this.panel()?.contains(e.target)) return
      if (window.matchMedia("(min-width: 640px)").matches) this.close()
    }
    this.onNavigate = () => this.key && this.close()

    window.addEventListener("pointerdown", this.onPointerDown, true)
    window.addEventListener("pointermove", this.onPointerMove, true)
    window.addEventListener("pointerup", this.cancelHold, true)
    window.addEventListener("pointercancel", this.cancelHold, true)
    window.addEventListener("contextmenu", this.onContextMenu, true)
    window.addEventListener("keydown", this.onKey)
    window.addEventListener("click", this.onOutside, true)
    window.addEventListener("scroll", this.onScroll, true)
    window.addEventListener("phx:navigate", this.onNavigate)

    this.el.addEventListener("click", (e) => {
      const item = e.target.closest("[data-menu-item]")
      // After the item's own phx-click has gone out, which needs the item.
      if (item && !item.hasAttribute("data-keep-open")) setTimeout(() => this.close())
    })
    this.el.addEventListener("input", (e) => {
      if (e.target.matches("[data-menu-filter]")) this.filter(e.target.value)
    })
  },

  updated() {
    if (this.el.dataset.open !== this.key) return
    this.place()
    const filter = this.el.querySelector("[data-menu-filter]")
    if (filter && filter.value) this.filter(filter.value)
  },

  destroyed() {
    window.removeEventListener("pointerdown", this.onPointerDown, true)
    window.removeEventListener("pointermove", this.onPointerMove, true)
    window.removeEventListener("pointerup", this.cancelHold, true)
    window.removeEventListener("pointercancel", this.cancelHold, true)
    window.removeEventListener("contextmenu", this.onContextMenu, true)
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("click", this.onOutside, true)
    window.removeEventListener("scroll", this.onScroll, true)
    window.removeEventListener("phx:navigate", this.onNavigate)
    document.documentElement.removeAttribute("data-card-menu")
  },

  cardAt(target) {
    const card = target instanceof Element && target.closest("[data-select-id][data-select-type]")
    return card && !this.el.contains(card) ? card : null
  },

  panel() {
    return this.el.querySelector("[data-card-menu-panel]")
  },

  open(card, x, y, keyboard = false) {
    this.key = key(card)
    this.openedAt = performance.now()
    this.point = {x, y}
    this.opener = keyboard ? card : null
    document.documentElement.setAttribute("data-card-menu", "")
    const [type, id] = [card.dataset.selectType, card.dataset.selectId]
    this.pushEventTo(this.el, "open", {type, id}, () => {
      if (this.key !== key(card)) return
      if (!this.panel()) return this.close(false, false)
      this.place()
      if (this.opener) this.panel().querySelector("[data-menu-item]")?.focus({preventScroll: true})
    })
  },

  close(restoreFocus = false, push = true) {
    if (!this.key) return
    this.key = null
    document.documentElement.removeAttribute("data-card-menu")
    if (restoreFocus && this.opener?.isConnected) this.opener.focus()
    this.opener = null
    if (push) this.pushEventTo(this.el, "close", {})
  },

  // Next to the pointer, inside the window; phones get the CSS sheet.
  place() {
    const panel = this.panel()
    if (!panel || !this.point) return
    if (!window.matchMedia("(min-width: 640px)").matches) {
      panel.style.left = panel.style.top = ""
      return
    }
    const {width, height} = panel.getBoundingClientRect()
    let {x, y} = this.point
    if (x + width > window.innerWidth - EDGE) x = Math.max(EDGE, x - width)
    if (y + height > window.innerHeight - EDGE) y = Math.max(EDGE, window.innerHeight - EDGE - height)
    panel.style.left = `${x}px`
    panel.style.top = `${y}px`
  },

  filter(text) {
    const q = text.trim().toLowerCase()
    let shown = 0
    this.el.querySelectorAll("[data-menu-item][data-label]").forEach((item) => {
      const hit = !q || item.dataset.label.toLowerCase().includes(q)
      item.hidden = !hit
      if (hit) shown++
    })
    const empty = this.el.querySelector("[data-menu-empty]")
    if (empty) empty.hidden = shown > 0
  },
}

const key = (card) => `${card.dataset.selectType}:${card.dataset.selectId}`

export default CardMenu
